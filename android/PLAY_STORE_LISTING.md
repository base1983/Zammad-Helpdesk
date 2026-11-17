# Play Store Listing — Helpdesk for Zammad (Android)

Copy-paste source for Play Console → Grow → Store presence → Main store listing.
Limits: app name 30, short description 80, full description 4000. Counts are
checked by `python3 android/tools/check_play_listing.py`.

The text is the App Store listing (`../APP_STORE_LISTING.md`) adapted to what
the Android app does: no icon badge, biometric lock instead of Face ID, Wear OS
instead of Apple Watch, Google Play billing wording instead of the Apple EULA.

Default language: **English (United States) – en-US**. Add `nl-NL`, `de-DE` and
`fr-FR` under "Manage translations → Add your own translations".

## Graphics (`play-store/`)

| Asset | File | Requirement |
| --- | --- | --- |
| App icon | `play-store/icon-512.png` | 512 × 512 PNG |
| Feature graphic | `play-store/feature-graphic.png` | 1024 × 500, no alpha |
| Phone screenshots | `play-store/phone/<lang>/` | 1080 × 1920 (9:16), 2–8 per language |
| 7-inch tablet | `play-store/tablet-7/` | 1200 × 1920 |
| 10-inch tablet | `play-store/tablet-10/` | 1600 × 2560 |

Screenshots were captured from the debug build in the emulator against the
demo server, with ads blocked. English has seven phone screenshots; Dutch, German
and French have six, because the New Ticket screen still shows English labels
in those languages (they are English in the iOS source strings). The tablet
sets are English only. Ticket data is English in every language,
because it comes from the demo Zammad. There is no chat conversation
screenshot: the demo chat must stay empty before a review
(`../demo-server/README.md`). There are no Wear OS screenshots yet (no Wear
emulator on the build machine); Play requires at least one before the Wear
form factor can be published.

## Store settings

| Field | Value |
| --- | --- |
| App category | Productivity |
| Tags | Business, Productivity |
| Contact e-mail | the support address used for the App Store listing |
| Website | `https://base1983.github.io/Zammad-Helpdesk/` |
| Privacy policy | `https://base1983.github.io/Zammad-Helpdesk/privacy.html` |
| Price | Free, contains ads, in-app purchases |

The privacy policy currently describes the iOS app. Before publishing, check
that it also names Android, Google Play billing, Firebase Cloud Messaging and
the advertising id.

---

## English (en-US)

**App name**
```
Helpdesk for Zammad
```

**Short description**
```
Unofficial Zammad client: tickets, replies, time logging, encrypted team chat.
```

**Full description**
```
Manage your Zammad helpdesk straight from your Android phone, tablet and Wear OS watch. Pick up a ticket in the queue, answer a customer, log your time and hand work to a colleague — without opening a laptop.

PLEASE NOTE: This is an independent, unofficial client for Zammad. It is not made, published, endorsed or supported by Zammad GmbH. You need your own Zammad server and an agent account to use it. "Zammad" is a trademark of its respective owner.

YOUR QUEUE, WHEREVER YOU ARE
• My tickets, unassigned and all open tickets in one tap
• Filter by status and search across your queue
• Unread markers so you always see what changed
• Full conversation history with formatted articles and attachments

REPLY AND RESOLVE
• Public replies or internal notes, with photo and file attachments
• Create new tickets with customer search, group and tags
• Change status, priority and owner
• Hand a ticket to a colleague with a note — Zammad notifies them
• Log spent time against your Zammad activity types

TEAM CHAT, END-TO-END ENCRYPTED
• Message colleagues one-to-one or in groups
• Reference a ticket so everyone has the context
• Send files and photos
• Messages are encrypted on your device and only readable by the recipients
• Works together with the iPhone version of the app
• Choose your own history retention, from 30 days to forever

STAY IN THE LOOP
• Real-time push notifications when tickets are created or updated
• Tap a notification to jump straight to the ticket
• Background refresh keeps the queue current

BUILT FOR THE WAY YOU WORK
• Guided setup wizard: API token, password or single sign-on, with a connection test
• Fingerprint, face or PIN lock on the whole app
• Light and dark themes, 14 wallpapers and a choice of chat themes
• Wear OS app for a glance at your queue
• Available in English, Dutch, German and French

PRIVACY AND SECURITY
Your tickets stay between your device and your own Zammad server — there is no account to create and no middleman for your helpdesk data. Your API token is stored encrypted on your device. Chat messages are end-to-end encrypted, so the relay used to deliver them only ever holds ciphertext.

FREE, WITH AN OPTIONAL PREMIUM UNLOCK
The app is free and ad-supported. Premium removes all ads, enables real-time notifications and SLA deadline alerts, and supports continued development. Choose a monthly or yearly auto-renewing subscription, or a one-time Lifetime Unlock with no recurring charge.
Subscriptions are charged to your Google Play account and renew automatically unless you cancel at least 24 hours before the end of the current period. You can manage or cancel them under Subscriptions in Google Play.
Privacy Policy: https://base1983.github.io/Zammad-Helpdesk/privacy.html

REQUIREMENTS
• A reachable Zammad installation (self-hosted or cloud), served over HTTPS
• An agent account and an API token with at least ticket.agent rights
• Real-time notifications need one webhook configured in Zammad — the app includes a step-by-step guide

NOT AFFILIATED WITH ZAMMAD GMBH
This app is a third-party product developed independently. It is not affiliated with, authorised by, or supported by Zammad GmbH. For questions about the app, contact us — not Zammad. For questions about your Zammad server, contact your administrator.
```

---

## Nederlands (nl-NL)

**App name**
```
Helpdesk voor Zammad
```

**Short description**
```
Onofficiële Zammad-client: tickets, antwoorden, tijd schrijven, veilige chat.
```

**Full description**
```
Beheer uw Zammad-helpdesk rechtstreeks vanaf uw Android-telefoon, tablet en Wear OS-horloge. Pak een ticket op uit de wachtrij, beantwoord een klant, schrijf uw tijd en draag werk over aan een collega — zonder uw laptop open te klappen.

LET OP: Dit is een onafhankelijke, onofficiële client voor Zammad. De app is niet gemaakt, uitgegeven, goedgekeurd of ondersteund door Zammad GmbH. U hebt uw eigen Zammad-server en een agent-account nodig. "Zammad" is een handelsmerk van de rechtmatige eigenaar.

UW WACHTRIJ, WAAR U OOK BENT
• Mijn tickets, niet-toegewezen en alle open tickets met één tik
• Filter op status en zoek door uw hele wachtrij
• Ongelezen-markeringen, zodat u altijd ziet wat er is veranderd
• Volledige gespreksgeschiedenis met opgemaakte berichten en bijlagen

REAGEREN EN AFHANDELEN
• Openbare antwoorden of interne notities, met foto's en bestanden
• Nieuwe tickets aanmaken met klant zoeken, groep en tags
• Status, prioriteit en eigenaar wijzigen
• Een ticket met een notitie overdragen aan een collega — Zammad stelt uw collega op de hoogte
• Bestede tijd wegschrijven op uw Zammad-activiteiten

TEAMCHAT MET END-TO-END-VERSLEUTELING
• Chat één-op-één of in groepen met collega's
• Verwijs naar een ticket, zodat iedereen de context heeft
• Verstuur bestanden en foto's
• Berichten worden op uw toestel versleuteld en zijn alleen leesbaar voor de ontvangers
• Werkt samen met de iPhone-versie van de app
• Kies zelf hoe lang de geschiedenis bewaard blijft, van 30 dagen tot altijd

ALTIJD OP DE HOOGTE
• Realtime pushmeldingen bij nieuwe of gewijzigde tickets
• Tik op een melding en ga direct naar het ticket
• Achtergrondverversing houdt de wachtrij actueel

GEMAAKT VOOR UW MANIER VAN WERKEN
• Stapsgewijze installatiewizard: API-token, wachtwoord of single sign-on, met verbindingstest
• Vergrendeling met vingerafdruk, gezicht of pincode voor de hele app
• Lichte en donkere thema's, 14 achtergronden en een keuze aan chatthema's
• Wear OS-app voor een snelle blik op uw wachtrij
• Beschikbaar in het Nederlands, Engels, Duits en Frans

PRIVACY EN BEVEILIGING
Uw tickets blijven tussen uw toestel en uw eigen Zammad-server — u hoeft geen account aan te maken en er zit geen tussenpartij op uw helpdeskgegevens. Uw API-token wordt versleuteld op uw toestel bewaard. Chatberichten zijn end-to-end versleuteld, zodat de server die ze aflevert alleen versleutelde tekst in handen heeft.

GRATIS, MET OPTIONELE PREMIUM-ONTGRENDELING
De app is gratis en wordt ondersteund door advertenties. Met Premium verdwijnen alle advertenties, krijgt u realtime meldingen en waarschuwingen bij SLA-deadlines, en steunt u de verdere ontwikkeling. Kies een maandelijks of jaarlijks abonnement dat automatisch wordt verlengd, of de eenmalige Lifetime-ontgrendeling zonder terugkerende kosten.
Abonnementen worden via uw Google Play-account afgerekend en automatisch verlengd, tenzij u ze minimaal 24 uur voor het einde van de lopende periode opzegt. Beheren of opzeggen doet u onder Abonnementen in Google Play.
Privacybeleid: https://base1983.github.io/Zammad-Helpdesk/privacy.html

VEREISTEN
• Een bereikbare Zammad-installatie (self-hosted of cloud), via HTTPS
• Een agent-account en een API-token met minimaal ticket.agent-rechten
• Voor realtime meldingen configureert u één webhook in Zammad — de app bevat een stapsgewijze handleiding

NIET VERBONDEN AAN ZAMMAD GMBH
Deze app is een onafhankelijk ontwikkeld product van derden. De app is niet verbonden aan, geautoriseerd door of ondersteund door Zammad GmbH. Neem bij vragen over de app contact met ons op — niet met Zammad. Voor vragen over uw Zammad-server neemt u contact op met uw beheerder.
```

---

## Deutsch (de-DE)

**App name**
```
Helpdesk für Zammad
```

**Short description**
```
Inoffizieller Zammad-Client: Tickets, Antworten, Zeiterfassung, sicherer Chat.
```

**Full description**
```
Verwalten Sie Ihren Zammad-Helpdesk direkt vom Android-Smartphone, vom Tablet und von der Wear OS-Uhr aus. Nehmen Sie ein Ticket aus der Warteschlange, antworten Sie einem Kunden, erfassen Sie Ihre Zeit und übergeben Sie Arbeit an Kolleginnen und Kollegen — ohne den Laptop aufzuklappen.

BITTE BEACHTEN: Dies ist ein unabhängiger, inoffizieller Client für Zammad. Die App wird nicht von der Zammad GmbH entwickelt, herausgegeben, unterstützt oder empfohlen. Sie benötigen einen eigenen Zammad-Server und ein Agenten-Konto. „Zammad“ ist eine Marke des jeweiligen Inhabers.

IHRE WARTESCHLANGE, ÜBERALL
• Meine Tickets, nicht zugewiesene und alle offenen Tickets mit einem Tippen
• Nach Status filtern und die gesamte Warteschlange durchsuchen
• Ungelesen-Markierungen, damit Sie sofort sehen, was sich geändert hat
• Vollständiger Gesprächsverlauf mit formatierten Artikeln und Anhängen

ANTWORTEN UND ERLEDIGEN
• Öffentliche Antworten oder interne Notizen, mit Fotos und Dateien
• Neue Tickets anlegen — mit Kundensuche, Gruppe und Tags
• Status, Priorität und Besitzer ändern
• Ein Ticket mit einer Notiz übergeben — Zammad benachrichtigt die Kollegin oder den Kollegen
• Aufgewendete Zeit auf Ihre Zammad-Aktivitäten buchen

TEAM-CHAT, ENDE-ZU-ENDE-VERSCHLÜSSELT
• Einzel- und Gruppenchats mit Kolleginnen und Kollegen
• Auf ein Ticket verweisen, damit alle den Kontext haben
• Dateien und Fotos senden
• Nachrichten werden auf Ihrem Gerät verschlüsselt und sind nur für die Empfänger lesbar
• Funktioniert zusammen mit der iPhone-Version der App
• Aufbewahrungsdauer selbst wählen — von 30 Tagen bis unbegrenzt

IMMER AUF DEM LAUFENDEN
• Push-Benachrichtigungen in Echtzeit bei neuen und geänderten Tickets
• Auf eine Mitteilung tippen und direkt im Ticket landen
• Die Hintergrundaktualisierung hält die Warteschlange aktuell

FÜR IHREN ARBEITSALLTAG GEBAUT
• Geführte Einrichtung: API-Token, Passwort oder Single Sign-on, mit Verbindungstest
• Sperre per Fingerabdruck, Gesicht oder PIN für die gesamte App
• Helles und dunkles Design, 14 Hintergründe und eine Auswahl an Chat-Designs
• Wear OS-App für den schnellen Blick auf die Warteschlange
• Verfügbar auf Deutsch, Englisch, Niederländisch und Französisch

DATENSCHUTZ UND SICHERHEIT
Ihre Tickets bleiben zwischen Ihrem Gerät und Ihrem eigenen Zammad-Server — kein Konto, keine Zwischenstation für Ihre Helpdesk-Daten. Ihr API-Token wird verschlüsselt auf dem Gerät gespeichert. Chat-Nachrichten sind Ende-zu-Ende-verschlüsselt, sodass der zustellende Server ausschließlich verschlüsselten Text sieht.

KOSTENLOS, MIT OPTIONALER PREMIUM-FREISCHALTUNG
Die App ist kostenlos und werbefinanziert. Premium entfernt alle Werbung, aktiviert Echtzeit-Benachrichtigungen und Warnungen bei SLA-Fristen und unterstützt die Weiterentwicklung. Wählen Sie ein monatliches oder jährliches Abonnement mit automatischer Verlängerung oder die einmalige Lifetime-Freischaltung ohne wiederkehrende Kosten.
Abonnements werden über Ihr Google Play-Konto abgerechnet und verlängern sich automatisch, sofern sie nicht mindestens 24 Stunden vor Ablauf des laufenden Zeitraums gekündigt werden. Verwalten oder kündigen können Sie sie unter Abos in Google Play.
Datenschutzrichtlinie: https://base1983.github.io/Zammad-Helpdesk/privacy.html

VORAUSSETZUNGEN
• Eine erreichbare Zammad-Installation (selbst gehostet oder Cloud), über HTTPS
• Ein Agenten-Konto und ein API-Token mit mindestens ticket.agent-Rechten
• Für Echtzeit-Benachrichtigungen ein Webhook in Zammad — die App enthält eine Schritt-für-Schritt-Anleitung

KEINE VERBINDUNG ZUR ZAMMAD GMBH
Diese App ist ein unabhängig entwickeltes Produkt eines Drittanbieters. Sie steht in keiner Verbindung zur Zammad GmbH und wird von dieser weder autorisiert noch unterstützt. Bei Fragen zur App wenden Sie sich bitte an uns — nicht an Zammad. Bei Fragen zu Ihrem Zammad-Server wenden Sie sich an Ihre Administration.
```

---

## Français (fr-FR)

**App name**
```
Helpdesk pour Zammad
```

**Short description**
```
Client Zammad non officiel : tickets, réponses, suivi du temps, chat chiffré.
```

**Full description**
```
Gérez votre helpdesk Zammad directement depuis votre téléphone Android, votre tablette et votre montre Wear OS. Prenez un ticket dans la file, répondez à un client, enregistrez votre temps et transmettez le travail à un collègue — sans ouvrir votre ordinateur.

À NOTER : il s'agit d'un client indépendant et non officiel pour Zammad. Cette application n'est ni développée, ni publiée, ni approuvée, ni prise en charge par Zammad GmbH. Vous devez disposer de votre propre serveur Zammad et d'un compte agent. « Zammad » est une marque de son propriétaire respectif.

VOTRE FILE, OÙ QUE VOUS SOYEZ
• Mes tickets, tickets non attribués et tous les tickets ouverts en un geste
• Filtrez par statut et recherchez dans toute votre file
• Marqueurs de non-lu pour repérer d'un coup d'œil ce qui a changé
• Historique complet des échanges, avec mise en forme et pièces jointes

RÉPONDRE ET RÉSOUDRE
• Réponses publiques ou notes internes, avec photos et fichiers
• Créez des tickets avec recherche de client, groupe et étiquettes
• Modifiez le statut, la priorité et le propriétaire
• Transmettez un ticket à un collègue avec un mot — Zammad le prévient
• Enregistrez le temps passé sur vos activités Zammad

MESSAGERIE D'ÉQUIPE CHIFFRÉE DE BOUT EN BOUT
• Discutez avec vos collègues en tête-à-tête ou en groupe
• Référencez un ticket pour que chacun ait le contexte
• Envoyez des fichiers et des photos
• Les messages sont chiffrés sur votre appareil et lisibles uniquement par les destinataires
• Compatible avec la version iPhone de l'application
• Choisissez la durée de conservation, de 30 jours à illimitée

RESTEZ INFORMÉ
• Notifications push en temps réel à la création ou à la mise à jour d'un ticket
• Touchez une notification pour ouvrir directement le ticket concerné
• L'actualisation en arrière-plan garde votre file à jour

PENSÉE POUR VOTRE FAÇON DE TRAVAILLER
• Assistant de configuration : jeton d'API, mot de passe ou authentification unique, avec test de connexion
• Verrouillage de l'application par empreinte, visage ou code
• Thèmes clair et sombre, 14 fonds d'écran et un choix de thèmes de discussion
• Application Wear OS pour un coup d'œil sur votre file
• Disponible en français, anglais, néerlandais et allemand

CONFIDENTIALITÉ ET SÉCURITÉ
Vos tickets restent entre votre appareil et votre propre serveur Zammad : aucun compte à créer, aucun intermédiaire sur vos données. Votre jeton d'API est conservé chiffré sur votre appareil. Les messages sont chiffrés de bout en bout : le serveur qui les achemine ne détient que du texte chiffré.

GRATUIT, AVEC UN DÉBLOCAGE PREMIUM FACULTATIF
L'application est gratuite et financée par la publicité. Premium supprime toute publicité, active les notifications en temps réel et les alertes d'échéance SLA, et soutient le développement. Choisissez un abonnement mensuel ou annuel à renouvellement automatique, ou le déblocage à vie en un seul achat, sans frais récurrents.
Les abonnements sont facturés sur votre compte Google Play et se renouvellent automatiquement, sauf annulation au moins 24 heures avant la fin de la période en cours. Vous pouvez les gérer ou les annuler dans la rubrique Abonnements de Google Play.
Politique de confidentialité : https://base1983.github.io/Zammad-Helpdesk/privacy.html

CONFIGURATION REQUISE
• Une installation Zammad accessible (auto-hébergée ou dans le cloud), en HTTPS
• Un compte agent et un jeton d'API disposant au minimum des droits ticket.agent
• Pour les notifications en temps réel, un webhook à configurer dans Zammad — un guide pas à pas est inclus

AUCUN LIEN AVEC ZAMMAD GMBH
Cette application est un produit tiers développé de façon indépendante. Elle n'est ni affiliée à Zammad GmbH, ni autorisée ou prise en charge par cette société. Pour toute question sur l'application, contactez-nous — pas Zammad. Pour toute question sur votre serveur Zammad, adressez-vous à votre administrateur.
```
