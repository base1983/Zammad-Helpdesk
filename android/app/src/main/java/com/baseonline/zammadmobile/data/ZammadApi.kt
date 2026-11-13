package com.baseonline.zammadmobile.data

import android.content.Context
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.serializer
import android.security.NetworkSecurityPolicy
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.IOException
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

sealed class ApiException(message: String) : Exception(message) {
    class InvalidResponse : ApiException("Invalid response from the server.")
    class Decoding : ApiException("Could not process data from the server.")
    class TokenNotSet : ApiException("API token not set. Please go to Settings.")
    class AuthenticationFailed : ApiException("Authentication failed. Please check your API token.")
    class UserNotFound : ApiException("Could not find the current user.")
    class InvalidURL : ApiException("The configured server URL is invalid.")
    class Network(cause: IOException) : ApiException(cause.localizedMessage ?: "Network error.")
    class Server(val statusCode: Int, val body: String?) : ApiException(describe(statusCode, body)) {
        /** Zammad's own `{"error": "..."}` text, when the body carries one. */
        val serverError: String? get() = parseError(body)
    }

    companion object {
        private fun parseError(body: String?): String? = try {
            body?.let { AppJson.parseToJsonElement(it).jsonObject["error"]?.jsonPrimitive?.content }
        } catch (e: Exception) { null }

        private fun describe(code: Int, body: String?) = parseError(body) ?: "Server error: Status $code."
    }
}

/** The only thing that talks to the user's Zammad server (`/api/v1/`). */
object ZammadApi {
    private const val TAG = "ZammadApi"
    val JSON_TYPE = "application/json".toMediaType()

    /**
     * Refuses plain HTTP unless the platform's network security policy allows
     * it for that host, so a server URL typed as `http://…` can never send the
     * API token unencrypted. The manifest already bans cleartext; this makes
     * the app not depend on the HTTP library honouring that. Checked on an
     * emulator with the release build: `http://neverssl.com` is refused here,
     * while loopback (127.0.0.1, used with tools/mock_zammad.py through
     * `adb reverse`) is permitted by Android itself and never leaves the device.
     */
    private val httpsOnly = Interceptor { chain ->
        val url = chain.request().url
        if (!url.isHttps && !NetworkSecurityPolicy.getInstance().isCleartextTrafficPermitted(url.host)) {
            throw IOException("Insecure connection refused: the server URL must start with https://")
        }
        chain.proceed(chain.request())
    }

    val client: OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(httpsOnly)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

    /** No redirects and no cookie jar: used for the token-minting calls. */
    private val bareClient: OkHttpClient = client.newBuilder().followRedirects(false).build()

    /** Normalises what the user typed into `https://host/api/v1/`. */
    fun baseUrl(from: String? = null): String {
        var url = (from ?: SettingsManager.loadServerURL()).trim()
        if (url.isEmpty()) throw ApiException.InvalidURL()
        if (!url.lowercase().startsWith("http")) url = "https://$url"
        url = url.trimEnd('/')
        if (!url.endsWith("/api/v1")) url += "/api/v1"
        return "$url/"
    }

    /** `https://host` without the API suffix, for opening tickets in a browser. */
    fun webBaseUrl(from: String? = null): String = baseUrl(from).removeSuffix("api/v1/").trimEnd('/')

    private fun request(endpoint: String, method: String = "GET", body: String? = null,
                        url: String? = null, token: String? = null): Request {
        val base = baseUrl(url)
        val finalToken = (token ?: SettingsManager.loadToken())?.takeIf { it.isNotEmpty() }
            ?: throw ApiException.TokenNotSet()
        val builder = try {
            Request.Builder().url(base + endpoint)
        } catch (e: IllegalArgumentException) {
            throw ApiException.InvalidURL()
        }
        builder.header("Authorization", "Token token=$finalToken")
        builder.header("Content-Type", "application/json")
        builder.method(method, body?.toRequestBody(JSON_TYPE) ?: if (method == "GET") null else "".toRequestBody(JSON_TYPE))
        return builder.build()
    }

    private suspend fun execute(request: Request, client: OkHttpClient = this.client): ByteArray = withContext(Dispatchers.IO) {
        try {
            client.newCall(request).execute().use { response ->
                val bytes = response.body.bytes()
                if (response.code == 401) {
                    val text = String(bytes)
                    if (text.isNotEmpty()) throw ApiException.Server(401, text)
                    throw ApiException.AuthenticationFailed()
                }
                if (response.code !in 200..299) {
                    Log.w(TAG, "Server error ${response.code} on ${request.url.encodedPath}")
                    throw ApiException.Server(response.code, String(bytes))
                }
                bytes
            }
        } catch (e: IOException) {
            throw ApiException.Network(e)
        }
    }

    private suspend inline fun <reified T> fetch(request: Request): T {
        val bytes = execute(request)
        return try {
            AppJson.decodeFromString(serializer<T>(), String(bytes))
        } catch (e: Exception) {
            Log.w(TAG, "Decoding ${T::class.simpleName} failed: ${e.message}")
            throw ApiException.Decoding()
        }
    }

    private fun enc(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    // --- Authentication ---

    suspend fun testConnection(url: String, token: String): Boolean = try {
        fetch<User>(request("users/me", url = url, token = token)); true
    } catch (e: Exception) {
        Log.w(TAG, "Connection test failed: ${e.message}"); false
    }

    /** Permissions requested for a minted token; Zammad grants only what the user has. */
    private val tokenPermissions = listOf(
        "ticket.agent", "ticket.customer", "user_preferences.notifications", "user_preferences.password",
        "user_preferences.access_token", "user_preferences.language", "user_preferences.avatar",
        "user_preferences.calendar", "user_preferences.device", "user_preferences.out_of_office",
        "cti.agent", "chat.agent", "knowledge_base.editor", "knowledge_base.reader", "report",
        "admin.user", "admin.organization", "admin.group", "admin.role", "admin.tag",
    )

    @Serializable private data class TokenResponse(val token: String)

    private fun tokenBody(tokenName: String) = buildJsonObject {
        put("name", tokenName)
        put("permission", JsonArray(tokenPermissions.map { JsonPrimitive(it) }))
    }.toString()

    /**
     * Logs in with username/password (HTTP Basic) and has Zammad mint a personal
     * access token. The password is never stored; only the token is returned.
     */
    suspend fun createAccessToken(url: String, username: String, password: String, tokenName: String): String {
        val basic = Base64.encodeToString("$username:$password".toByteArray(), Base64.NO_WRAP)
        val request = Request.Builder().url(baseUrl(url) + "user_access_token")
            .header("Authorization", "Basic $basic")
            .post(tokenBody(tokenName).toRequestBody(JSON_TYPE)).build()
        val bytes = try { execute(request, bareClient) } catch (e: ApiException.Server) {
            if (e.statusCode == 401) throw ApiException.AuthenticationFailed() else throw e
        }
        return try { AppJson.decodeFromString(TokenResponse.serializer(), String(bytes)).token }
        catch (e: Exception) { throw ApiException.Decoding() }
    }

    /**
     * Uses an existing Zammad browser session (cookies captured from the SSO
     * WebView plus the page's CSRF token) to mint a personal access token.
     */
    suspend fun createAccessTokenWithSession(url: String, cookieHeader: String, csrfToken: String?, tokenName: String): String {
        val builder = Request.Builder().url(baseUrl(url) + "user_access_token")
            .header("Accept", "application/json")
            .post(tokenBody(tokenName).toRequestBody(JSON_TYPE))
        if (cookieHeader.isNotEmpty()) builder.header("Cookie", cookieHeader)
        if (!csrfToken.isNullOrEmpty()) builder.header("X-CSRF-Token", csrfToken)
        val bytes = try { execute(builder.build(), bareClient) } catch (e: ApiException.Server) {
            if (e.statusCode == 401) throw ApiException.AuthenticationFailed()
            throw ApiException.Server(e.statusCode, "HTTP ${e.statusCode}: ${e.body?.take(200)}")
        }
        return try { AppJson.decodeFromString(TokenResponse.serializer(), String(bytes)).token }
        catch (e: Exception) { throw ApiException.Decoding() }
    }

    // --- Tickets ---

    suspend fun searchTickets(query: String): List<Ticket> =
        fetch(request("tickets/search?query=${enc(query)}&expand=true&per_page=200"))

    @Serializable private data class CountResponse(val total_count: Int = 0)

    /** Number of tickets matching a search, without transferring the tickets. */
    suspend fun countTickets(query: String): Int =
        fetch<CountResponse>(request("tickets/search?query=${enc(query)}&only_total_count=true")).total_count

    suspend fun fetchTicketsByStatus(id: Int): List<Ticket> =
        fetch(request("tickets/search?query=${enc("state_id:$id")}&expand=true&per_page=200"))

    suspend fun fetchTicket(id: Int): Ticket = fetch(request("tickets/$id?expand=true"))
    suspend fun fetchTicketStates(): List<TicketState> = fetch(request("ticket_states"))
    suspend fun fetchTicketPriorities(): List<TicketPriority> = fetch(request("ticket_priorities"))
    suspend fun fetchArticles(ticketId: Int): List<TicketArticle> = fetch(request("ticket_articles/by_ticket/$ticketId"))
    suspend fun fetchCurrentUser(): User = fetch(request("users/me"))
    suspend fun fetchRoles(): List<Role> = fetch(request("roles"))
    suspend fun fetchGroups(): List<TicketGroup> = fetch(request("groups"))

    suspend fun fetchAllUsers(): List<User> = paged { page -> fetch(request("users?page=$page&per_page=100&expand=true")) }
    suspend fun fetchOrganizations(): List<Organization> = paged { page -> fetch(request("organizations?page=$page&per_page=100")) }

    private suspend fun <T> paged(load: suspend (Int) -> List<T>): List<T> {
        val all = mutableListOf<T>()
        var page = 1
        while (true) {
            val items = load(page)
            all += items
            if (items.size < 100 || page >= 200) break
            page++
        }
        return all
    }

    suspend fun searchUsers(query: String): List<User> =
        fetch(request("users/search?query=${enc(query)}&limit=30"))

    suspend fun updateTicket(id: Int, payload: TicketUpdatePayload): Ticket =
        fetch(request("tickets/$id", "PUT", AppJson.encodeToString(TicketUpdatePayload.serializer(), payload)))

    suspend fun createArticle(payload: ArticleCreationPayload): TicketArticle =
        fetch(request("ticket_articles", "POST", AppJson.encodeToString(ArticleCreationPayload.serializer(), payload)))

    suspend fun createTicket(payload: TicketCreationPayload): Ticket =
        fetch(request("tickets", "POST", AppJson.encodeToString(TicketCreationPayload.serializer(), payload)))

    // --- Time accounting ---

    suspend fun fetchTimeAccountingTypes(): List<TimeAccountingType> = fetch(request("time_accounting/types"))

    suspend fun createTimeAccounting(ticketId: Int, payload: TimeAccountingPayload): TimeAccounting =
        fetch(request("tickets/$ticketId/time_accountings", "POST",
            AppJson.encodeToString(TimeAccountingPayload.serializer(), payload)))

    suspend fun fetchTimeAccountings(ticketId: Int): List<TimeAccounting> =
        fetch(request("tickets/$ticketId/time_accountings"))

    /** Runs [block]; endpoints an agent may lack permission for degrade to [fallback]. */
    suspend fun <T> gracefully(fallback: T, block: suspend () -> T): T = try {
        block()
    } catch (e: kotlinx.coroutines.CancellationException) {
        throw e
    } catch (e: Exception) {
        Log.i(TAG, "Optional endpoint failed, continuing without: ${e.message}"); fallback
    }

    // --- Mentions & tags ---

    /** Subscribes a user to a ticket so they are notified about it (handoff). */
    suspend fun createMention(ticketId: Int, userId: Int) {
        val body = buildJsonObject {
            put("mentionable_type", "Ticket"); put("mentionable_id", ticketId); put("user_id", userId)
        }.toString()
        execute(request("mentions", "POST", body))
    }

    /** Adds a tag; adding one that is already present is a no-op on the server. */
    suspend fun addTag(ticketId: Int, tag: String) {
        val body = buildJsonObject { put("object", "Ticket"); put("o_id", ticketId); put("item", tag) }.toString()
        execute(request("tags/add", "POST", body))
    }

    // --- Attachments ---

    suspend fun downloadAttachmentBytes(ticketId: Int, articleId: Int, attachmentId: Int): ByteArray =
        execute(request("ticket_attachment/$ticketId/$articleId/$attachmentId"))

    /** Downloads into the cache dir (shared through the FileProvider) and returns the file. */
    suspend fun downloadAttachment(context: Context, ticketId: Int, articleId: Int, attachment: Attachment): File {
        val bytes = downloadAttachmentBytes(ticketId, articleId, attachment.id)
        return withContext(Dispatchers.IO) {
            val dir = File(context.cacheDir, "attachments").apply { mkdirs() }
            val safeName = attachment.filename.replace(Regex("[/\\\\:]"), "_").ifEmpty { "attachment" }
            File(dir, "${attachment.id}_$safeName").apply { writeBytes(bytes) }
        }
    }
}
