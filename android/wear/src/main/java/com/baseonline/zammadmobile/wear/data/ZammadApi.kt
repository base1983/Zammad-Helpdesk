package com.baseonline.zammadmobile.wear.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.URLEncoder
import java.time.Instant
import java.time.OffsetDateTime
import java.util.concurrent.TimeUnit

@Serializable
data class Ticket(
    val id: Int = 0,
    val number: String = "",
    val title: String = "",
    val state_id: Int = 0,
    val priority_id: Int = 0,
    val owner_id: Int = 1,
    val customer_id: Int = 0,
    val pending_time: String? = null,
    val created_at: String = "",
    val updated_at: String = "",
)

@Serializable
data class TicketState(val id: Int = 0, val name: String = "")

@Serializable
data class TicketPriority(val id: Int = 0, val name: String = "")

@Serializable
data class Role(val id: Int = 0, val name: String = "")

@Serializable
data class User(
    val id: Int = 0,
    val login: String = "",
    val firstname: String = "",
    val lastname: String = "",
    val role_ids: List<Int> = emptyList(),
) {
    val fullname: String get() = "$firstname $lastname".trim().ifEmpty { login }
}

sealed class ApiException(message: String) : Exception(message) {
    class NoCredentials : ApiException("No credentials")
    class InvalidUrl : ApiException("Invalid server URL")
    class AuthenticationFailed : ApiException("Authentication failed")
    class Decoding(cause: Throwable) : ApiException("Decoding failed: ${cause.message}")
    class Network(cause: Throwable) : ApiException("Network error: ${cause.message}")
    /** [serverMessage] is the `error` field of Zammad's JSON error body, if any. */
    class Server(val code: Int, val serverMessage: String?) : ApiException("Server error $code")
}

/** ISO 8601 with optional fractional seconds; null when absent or unparsable. */
fun parseIsoDate(value: String?): Instant? {
    if (value.isNullOrEmpty()) return null
    return try {
        OffsetDateTime.parse(value).toInstant()
    } catch (e: Exception) {
        try { Instant.parse(value) } catch (e2: Exception) { null }
    }
}

/** Direct HTTPS client for the user's Zammad server (`/api/v1/`). */
object ZammadApi {
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private val jsonMedia = "application/json; charset=utf-8".toMediaType()
    private val client = OkHttpClient.Builder()
        // HTTPS only: OkHttp does not enforce the manifest's cleartext ban by
        // itself, and the API token must never travel unencrypted.
        .addInterceptor { chain ->
            if (!chain.request().url.isHttps) throw java.io.IOException("Insecure connection refused (https only).")
            chain.proceed(chain.request())
        }
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private fun baseUrl(serverUrl: String): String {
        var url = serverUrl.trim()
        if (url.isEmpty()) throw ApiException.InvalidUrl()
        if (!url.startsWith("http://", ignoreCase = true) && !url.startsWith("https://", ignoreCase = true)) {
            url = "https://$url"
        }
        return url.trimEnd('/') + "/api/v1/"
    }

    private suspend fun request(endpoint: String, method: String = "GET", body: String? = null): String =
        withContext(Dispatchers.IO) {
            val credentials = CredentialStore.state.value ?: throw ApiException.NoCredentials()
            val request = try {
                Request.Builder()
                    .url(baseUrl(credentials.serverUrl) + endpoint)
                    .header("Authorization", "Token token=${credentials.token}")
                    .header("Accept", "application/json")
                    .method(method, body?.toRequestBody(jsonMedia))
                    .build()
            } catch (e: IllegalArgumentException) {
                throw ApiException.InvalidUrl()
            }
            try {
                client.newCall(request).execute().use { response ->
                    val text = response.body.string()
                    if (response.code == 401) throw ApiException.AuthenticationFailed()
                    if (!response.isSuccessful) {
                        val message = try {
                            json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.content
                        } catch (e: Exception) {
                            null
                        }
                        throw ApiException.Server(response.code, message)
                    }
                    text
                }
            } catch (e: IOException) {
                throw ApiException.Network(e)
            }
        }

    private inline fun <reified T> decode(text: String): T = try {
        json.decodeFromString<T>(text)
    } catch (e: SerializationException) {
        throw ApiException.Decoding(e)
    } catch (e: IllegalArgumentException) {
        throw ApiException.Decoding(e)
    }

    suspend fun fetchCurrentUser(): User = decode(request("users/me"))

    suspend fun fetchTicketStates(): List<TicketState> = decode(request("ticket_states"))

    suspend fun fetchTicketPriorities(): List<TicketPriority> = decode(request("ticket_priorities"))

    suspend fun fetchRoles(): List<Role> = decode(request("roles"))

    suspend fun fetchAllUsers(): List<User> {
        val all = mutableListOf<User>()
        val perPage = 100
        var page = 1
        while (true) {
            val batch: List<User> = decode(request("users?page=$page&per_page=$perPage&expand=true"))
            all += batch
            if (batch.size < perPage) break
            page++
        }
        return all
    }

    suspend fun searchTickets(query: String): List<Ticket> {
        val encoded = URLEncoder.encode(query, "UTF-8")
        return decode(request("tickets/search?query=$encoded&expand=true&per_page=200"))
    }

    suspend fun fetchTicket(id: Int): Ticket = decode(request("tickets/$id?expand=true"))

    suspend fun updateTicket(ticket: Ticket, pendingTime: String?): Ticket {
        val payload = buildJsonObject {
            put("owner_id", ticket.owner_id)
            put("state_id", ticket.state_id)
            put("priority_id", ticket.priority_id)
            put("customer_id", ticket.customer_id)
            if (pendingTime != null) put("pending_time", pendingTime)
        }
        return decode(request("tickets/${ticket.id}", "PUT", payload.toString()))
    }
}
