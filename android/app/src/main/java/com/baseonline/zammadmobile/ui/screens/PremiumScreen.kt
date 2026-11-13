package com.baseonline.zammadmobile.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessAlarm
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.android.billingclient.api.ProductDetails
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.managers.AdConsentManager
import com.baseonline.zammadmobile.managers.StoreManager
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.GlassCard
import com.baseonline.zammadmobile.ui.components.Pill
import com.baseonline.zammadmobile.ui.components.StyledSection
import kotlinx.coroutines.launch

private const val PRIVACY_POLICY_URL = "https://base1983.github.io/Zammad-Helpdesk/privacy.html"
private val PremiumGold = Color(0xFFFFCC00)

// The iOS `subscription_terms` text names the Apple ID and the App Store, so
// Android needs its own wording (no string resource for it yet).
private const val SUBSCRIPTION_TERMS_PLAY =
    "Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current " +
        "period. Payment is charged to your Google Play account; manage or cancel under Subscriptions in Google Play."

private fun openUrl(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        // No browser / Play Store on this device: nothing to open.
    }
}

/**
 * Full-screen Premium suggestion, the counterpart of the iOS `PremiumPromptView`:
 * what Premium brings, then the one shared purchase block. Closes by itself
 * once a purchase or restore made the user Premium.
 */
@Composable
fun PremiumScreen(onClose: () -> Unit) {
    val wasPremium = remember { SettingsManager.isPremium }
    val isPremium = SettingsManager.isPremium
    LaunchedEffect(isPremium) {
        // Purchase or restore succeeded: the screen has done its job.
        if (isPremium && !wasPremium) onClose()
    }

    AppScaffold(
        title = stringResource(R.string.premium_step_title),
        onBack = onClose,
        actions = { TextButton(onClick = onClose) { Text(stringResource(R.string.not_now)) } },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            GlassCard(Modifier.fillMaxWidth(), contentPadding = PaddingValues(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.WorkspacePremium, contentDescription = null, tint = PremiumGold,
                        modifier = Modifier.size(34.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.premium_step_title),
                        style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                }
                Text(stringResource(R.string.premium_prompt_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 12.dp))
            }
            PremiumContent()
        }
    }
}

/**
 * The Premium purchase block, shared by Settings, the Premium screen and the
 * setup wizard so the app has exactly one paywall (iOS `InAppPurchaseView`).
 * It does not scroll by itself: place it in a scrolling parent.
 *
 * Products can legitimately be missing (not created in Play Console yet, an
 * emulator without Play): then [StoreManager.storeMessage] and a retry are shown.
 */
@Composable
fun PremiumContent(
    modifier: Modifier = Modifier,
    showBenefits: Boolean = true,
    showAdPrivacyOptions: Boolean = true,
) {
    val context = LocalContext.current
    val activity = LocalActivity.current
    val scope = rememberCoroutineScope()

    val isPremium = SettingsManager.isPremium
    val isLoading = StoreManager.isLoadingProducts
    val busy = StoreManager.isTransactionInProgress
    val activeSubscription = StoreManager.activeSubscriptionId
    val hasLifetime = StoreManager.hasLifetime
    val message = StoreManager.storeMessage

    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (showBenefits && !isPremium) {
            GlassCard(Modifier.fillMaxWidth(), contentPadding = PaddingValues(16.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    BenefitRow(Icons.Filled.Block, R.string.premium_benefit_no_ads)
                    BenefitRow(Icons.Filled.NotificationsActive, R.string.premium_benefit_notifications)
                    BenefitRow(Icons.Filled.AccessAlarm, R.string.premium_benefit_sla)
                    BenefitRow(Icons.Filled.FavoriteBorder, R.string.premium_benefit_support)
                }
            }
        }

        StyledSection(title = stringResource(R.string.in_app_purchases)) {
            if (isPremium) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Star, contentDescription = null, tint = PremiumGold)
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.premium_user_message), fontWeight = FontWeight.Medium)
                }
            }

            if (isLoading) {
                if (isPremium) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.loading_products))
                }
            } else {
                // What is offered: everything to a non-Premium user; the owned
                // plan (plus the other subscription, to switch) to a Premium one.
                // The lifetime unlock is not offered next to a running
                // subscription, which would keep billing alongside it.
                val rows = buildList {
                    val monthly = StoreManager.monthlyProduct
                    val yearly = StoreManager.yearlyProduct
                    val lifetime = StoreManager.lifetimeProduct
                    when {
                        !isPremium -> {
                            monthly?.let { add(it to R.string.premium_description_monthly) }
                            yearly?.let { add(it to R.string.premium_description_yearly) }
                            lifetime?.let { add(it to R.string.premium_description_lifetime) }
                        }
                        hasLifetime -> lifetime?.let { add(it to R.string.premium_description_lifetime) }
                        activeSubscription != null -> {
                            monthly?.let { add(it to R.string.premium_description_monthly) }
                            yearly?.let { add(it to R.string.premium_description_yearly) }
                        }
                    }
                }
                rows.forEachIndexed { index, (product, description) ->
                    if (index > 0 || isPremium) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                    }
                    val owned = (product.productId == StoreManager.LIFETIME_ID && hasLifetime) ||
                        product.productId == activeSubscription
                    ProductRow(
                        product = product,
                        description = stringResource(description),
                        owned = owned,
                        enabled = !busy && !owned && activity != null,
                        onClick = { activity?.let { StoreManager.purchase(it, product) } },
                    )
                }

                if (!isPremium || message != null) {
                    if (message != null) {
                        Text(message, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
                    }
                    if (!StoreManager.hasProducts) {
                        TextButton(
                            onClick = { scope.launch { StoreManager.reload() } },
                            enabled = !busy,
                            modifier = Modifier.padding(horizontal = 4.dp),
                        ) { Text(stringResource(R.string.products_retry)) }
                    }
                }
            }
        }

        GlassCard(Modifier.fillMaxWidth(), contentPadding = PaddingValues(4.dp)) {
            if (!isPremium && !isLoading) {
                TextButton(onClick = { scope.launch { StoreManager.restorePurchases() } }, enabled = !busy) {
                    Text(stringResource(R.string.restore_purchases))
                }
            }
            if (activeSubscription != null) {
                TextButton(onClick = {
                    openUrl(context, "https://play.google.com/store/account/subscriptions?package=${context.packageName}")
                }) { Text(stringResource(R.string.manage_subscription)) }
            }

            // How renewal works plus the privacy policy; the link stays
            // reachable for Premium users too.
            if (!hasLifetime) {
                Text(stringResource(R.string.subscription_terms_play), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp))
            }
            TextButton(onClick = { openUrl(context, PRIVACY_POLICY_URL) }) {
                Text(stringResource(R.string.privacy_policy))
            }

            // Google's consent policy requires a lasting way to change the ad
            // consent choice; never shown to Premium users, who see no ads.
            if (showAdPrivacyOptions && !isPremium && AdConsentManager.isPrivacyOptionsRequired && activity != null) {
                TextButton(onClick = { AdConsentManager.presentPrivacyOptions(activity) }) {
                    Text(stringResource(R.string.ad_privacy_options))
                }
            }
        }
    }
}

@Composable
private fun BenefitRow(icon: ImageVector, textRes: Int) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(stringResource(textRes), style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun ProductRow(
    product: ProductDetails,
    description: String,
    owned: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Surface(onClick = onClick, enabled = enabled, color = Color.Transparent, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(product.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(description, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (owned) Pill(stringResource(R.string.current_plan), Color(0xFF34C759))
            }
            Spacer(Modifier.width(12.dp))
            Column(
                Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.tertiary.copy(alpha = 0.15f))
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                horizontalAlignment = Alignment.End,
            ) {
                Text(StoreManager.price(product) ?: "—", fontWeight = FontWeight.Bold)
                billingPeriodRes(product)?.let {
                    Text(stringResource(it), style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** "per month" / "per year" for subscriptions, null for the lifetime unlock. */
private fun billingPeriodRes(product: ProductDetails): Int? {
    val period = product.subscriptionOfferDetails?.firstOrNull()
        ?.pricingPhases?.pricingPhaseList?.lastOrNull()?.billingPeriod
    return when (period) {
        "P1M" -> R.string.billing_per_month
        "P1Y" -> R.string.billing_per_year
        "P1W" -> R.string.billing_per_week
        else -> null
    }
}
