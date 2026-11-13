package com.baseonline.zammadmobile.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.GlassCard

/** Explains how to add the webhook trigger in Zammad that feeds the push relay. */
@Composable
fun WebhookGuideScreen(nav: Nav) {
    AppScaffold(title = stringResource(R.string.webhook_guide_title), onBack = { nav.back() }) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            GlassCard(Modifier.fillMaxWidth(), contentPadding = PaddingValues(16.dp)) {
                Text(stringResource(R.string.webhook_guide_intro))
            }
            GuideStep(R.string.webhook_guide_step1_title, R.string.webhook_guide_step1_body)
            GuideStep(R.string.webhook_guide_step2_title, R.string.webhook_guide_step2_body)
            GuideStep(R.string.webhook_guide_step3_title, R.string.webhook_guide_step3_body)
            GuideStep(R.string.webhook_guide_step4_title, R.string.webhook_guide_step4_body)
        }
    }
}

@Composable
private fun GuideStep(title: Int, body: Int) {
    GlassCard(Modifier.fillMaxWidth(), contentPadding = PaddingValues(16.dp)) {
        Text(stringResource(title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(stringResource(body), Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
