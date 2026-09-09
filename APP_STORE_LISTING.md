# App Store Listing — Zammad Helpdesk

Copy-paste source for App Store Connect. Version 1.2 · iOS 26.0+ · iPhone, iPad, Apple Watch
Character limits are noted per field; counts are verified against the text below.

---

## 1. App Name (max 30)

```
Helpdesk for Zammad
```

Localized per storefront (see section 7): `Helpdesk voor Zammad` · `Helpdesk für Zammad` ·
`Helpdesk pour Zammad`.

> **Why the "for" form.** "Zammad" is a registered trademark of Zammad GmbH. App Review
> applies guideline 5.2.1 (Intellectual Property) to app names that lead with someone
> else's brand, and may ask for written permission to use it. The `X for Y` construction
> is the conventional, review-safe way to signal a third-party client.

**Already changed in the project:** `INFOPLIST_KEY_CFBundleDisplayName` is now `Helpdesk`
for both the iOS and watchOS targets, and the setup wizard's welcome line reads
"Welcome to Helpdesk for Zammad" in all four languages.

The home-screen label is deliberately shorter than the App Store name. iOS truncates icon
labels at roughly 12 characters, so "Helpdesk for Zammad" would render as "Helpdesk f…d".
A shortened name that is a substring of the store name is standard practice and passes
review. If you would rather have an exact match on the Home Screen and accept the
ellipsis, change both `INFOPLIST_KEY_CFBundleDisplayName` values in project.pbxproj.

---

## 2. Subtitle (max 30)

```
Unofficial mobile agent app
```

Alternatives:
- `Unofficial ticket client` (24)
- `Your ticket queue, on the go` (28)

---

## 3. Promotional Text (max 170 — editable without a new build)

```
Work your queue from anywhere: reply, reassign, log time and chat securely with your team. An independent, unofficial client for your own Zammad server.
```

Swap this for seasonal or release-specific messaging later; it updates without review.

---

## 4. Keywords (max 100 chars, comma-separated, no spaces)

```
ticket,support,servicedesk,itsm,itil,queue,sla,customer,selfhosted,inbox,agent,tickets,helpdesk
```

Do not repeat words already in the app name or subtitle — Apple indexes those separately,
so duplicating them wastes characters.

---

## 5. Description (max 4000)

Paste as-is. Prose paragraphs are deliberately on single lines — App Store Connect keeps
every line break you paste, so wrapped text would render as ragged hard breaks on the
product page.

```
Manage your Zammad helpdesk straight from your iPhone, iPad and Apple Watch. Pick up a ticket in the queue, answer a customer, log your time and hand work to a colleague — without opening a laptop.

PLEASE NOTE: This is an independent, unofficial client for Zammad. It is not made, published, endorsed or supported by Zammad GmbH. You need your own Zammad server and an agent account to use it. "Zammad" is a trademark of its respective owner.

YOUR QUEUE, WHEREVER YOU ARE
• My tickets, unassigned and all open tickets in one tap
• Filter by status and search across your queue
• Unread markers so you always see what changed
• Full conversation history with formatted articles and attachments

REPLY AND RESOLVE
• Public replies or internal notes, with photo and file attachments
• Create new tickets with customer search, group, type and tags
• Change status, priority, owner and pending time
• Hand a ticket to a colleague with a note — Zammad notifies them
• Log spent time against your Zammad activity types

TEAM CHAT, END-TO-END ENCRYPTED
• Message colleagues one-to-one or in groups
• Reference a ticket so everyone has the context
• Send files and photos
• Messages are encrypted on your device and only readable by the recipients
• Choose your own history retention, from 30 days to forever

STAY IN THE LOOP
• Real-time push notifications when tickets are created or updated
• Tap a notification to jump straight to the ticket
• App icon badge for what still needs you
• Background refresh keeps the queue current

BUILT FOR THE WAY YOU WORK
• Guided setup wizard: API token or single sign-on, with a connection test
• Face ID / Touch ID lock on the whole app
• Light and dark themes, 14 wallpapers and 18 chat themes
• Apple Watch app for a glance at your queue
• Available in English, Dutch, German and French

PRIVACY AND SECURITY
Your tickets stay between your device and your own Zammad server — there is no account to create and no middleman for your helpdesk data. Your API token is stored on your device. Chat messages are end-to-end encrypted, so the relay used to deliver them only ever holds ciphertext.

FREE, WITH AN OPTIONAL UNLOCK
The app is free and ad-supported. A one-time Lifetime Unlock removes all ads, enables real-time notifications and the icon badge, and supports continued development. No subscription, no recurring charge.

REQUIREMENTS
• A reachable Zammad installation (self-hosted or cloud)
• An agent account and an API token with at least ticket.agent rights
• Real-time notifications need one webhook configured in Zammad — the app includes a step-by-step guide

NOT AFFILIATED WITH ZAMMAD GMBH
This app is a third-party product developed independently. It is not affiliated with, authorised by, or supported by Zammad GmbH. For questions about the app, contact us — not Zammad. For questions about your Zammad server, contact your administrator.
```

---

## 6. What's New (max 4000) — version 1.2

```
• End-to-end encrypted team chat — one-to-one and group conversations, with ticket references, attachments and 18 chat themes
• Hand off a ticket to a colleague with a note, straight from the ticket
• Encryption indicator so you always know a message is protected
• New wallpapers and background picker for light and dark mode
• Reliability fixes for push delivery and faster ticket loading

Thanks for using the app. Feedback and bug reports are very welcome.
```

---

## 7. Localized listings — Dutch, German, French

Add these under **App Store Connect → your app → the language selector → Add Language**.
Each localization has its own 30/170/100/4000 limits; all counts below are verified.
The register matches the app's own translations: formal *u* in Dutch, *Sie* in German,
*vous* in French.

### 7.1 Nederlands (nl-NL)

**Naam (30)**
```
Helpdesk voor Zammad
```

**Ondertitel (30)**
```
Onofficiële app voor agents
```

**Promotietekst (170)**
```
Werk uw wachtrij overal weg: reageren, toewijzen, tijd schrijven en veilig chatten met uw team. Een onafhankelijke, onofficiële client voor uw eigen Zammad-server.
```

**Trefwoorden (100)**
```
ticket,support,servicedesk,itsm,itil,wachtrij,klant,melding,storing,beheer,tickets,agent
```

**Beschrijving (4000)**
```
Beheer uw Zammad-helpdesk rechtstreeks vanaf uw iPhone, iPad en Apple Watch. Pak een ticket op uit de wachtrij, beantwoord een klant, schrijf uw tijd en draag werk over aan een collega — zonder uw laptop open te klappen.

LET OP: Dit is een onafhankelijke, onofficiële client voor Zammad. De app is niet gemaakt, uitgegeven, goedgekeurd of ondersteund door Zammad GmbH. U hebt uw eigen Zammad-server en een agent-account nodig. "Zammad" is een handelsmerk van de rechtmatige eigenaar.

UW WACHTRIJ, WAAR U OOK BENT
• Mijn tickets, niet-toegewezen en alle open tickets met één tik
• Filter op status en zoek door uw hele wachtrij
• Ongelezen-markeringen, zodat u altijd ziet wat er is veranderd
• Volledige gespreksgeschiedenis met opgemaakte berichten en bijlagen

REAGEREN EN AFHANDELEN
• Openbare antwoorden of interne notities, met foto's en bestanden
• Nieuwe tickets aanmaken met klant zoeken, groep, type en tags
• Status, prioriteit, eigenaar en wachttijd wijzigen
• Een ticket met een notitie overdragen aan een collega — Zammad stelt uw collega op de hoogte
• Bestede tijd wegschrijven op uw Zammad-activiteiten

TEAMCHAT MET END-TO-END-VERSLEUTELING
• Chat één-op-één of in groepen met collega's
• Verwijs naar een ticket, zodat iedereen de context heeft
• Verstuur bestanden en foto's
• Berichten worden op uw toestel versleuteld en zijn alleen leesbaar voor de ontvangers
• Kies zelf hoe lang de geschiedenis bewaard blijft, van 30 dagen tot altijd

ALTIJD OP DE HOOGTE
• Realtime pushmeldingen bij nieuwe of gewijzigde tickets
• Tik op een melding en ga direct naar het ticket
• Badge op het app-icoon voor alles wat nog uw aandacht vraagt
• Achtergrondverversing houdt de wachtrij actueel

GEMAAKT VOOR UW MANIER VAN WERKEN
• Stapsgewijze installatiewizard: API-token of single sign-on, met verbindingstest
• Face ID / Touch ID-vergrendeling voor de hele app
• Lichte en donkere thema's, 14 achtergronden en 18 chatthema's
• Apple Watch-app voor een snelle blik op uw wachtrij
• Beschikbaar in het Nederlands, Engels, Duits en Frans

PRIVACY EN BEVEILIGING
Uw tickets blijven tussen uw toestel en uw eigen Zammad-server — u hoeft geen account aan te maken en er zit geen tussenpartij op uw helpdeskgegevens. Uw API-token wordt op uw toestel bewaard. Chatberichten zijn end-to-end versleuteld, zodat de server die ze aflevert alleen versleutelde tekst in handen heeft.

GRATIS, MET OPTIONELE ONTGRENDELING
De app is gratis en wordt ondersteund door advertenties. Met de eenmalige Lifetime-ontgrendeling verdwijnen alle advertenties, krijgt u realtime meldingen en de badge, en steunt u de verdere ontwikkeling. Geen abonnement, geen terugkerende kosten.

VEREISTEN
• Een bereikbare Zammad-installatie (self-hosted of cloud)
• Een agent-account en een API-token met minimaal ticket.agent-rechten
• Voor realtime meldingen configureert u één webhook in Zammad — de app bevat een stapsgewijze handleiding

NIET VERBONDEN AAN ZAMMAD GMBH
Deze app is een onafhankelijk ontwikkeld product van derden. De app is niet verbonden aan, geautoriseerd door of ondersteund door Zammad GmbH. Neem bij vragen over de app contact met ons op — niet met Zammad. Voor vragen over uw Zammad-server neemt u contact op met uw beheerder.
```

**Nieuw in deze versie (1.2)**
```
• End-to-end versleutelde teamchat — één-op-één en in groepen, met ticketverwijzingen, bijlagen en 18 chatthema's
• Draag een ticket met een notitie over aan een collega, direct vanuit het ticket
• Versleutelingsindicator, zodat u altijd ziet dat een bericht beschermd is
• Nieuwe achtergronden en een achtergrondkiezer voor lichte en donkere modus
• Verbeteringen in de bezorging van pushmeldingen en snellere laadtijden

Bedankt voor het gebruik van de app. Feedback en foutmeldingen zijn van harte welkom.
```

---

### 7.2 Deutsch (de-DE)

**Name (30)**
```
Helpdesk für Zammad
```

**Untertitel (30)**
```
Inoffizielle App für Agenten
```

**Werbetext (170)**
```
Arbeiten Sie Ihre Warteschlange überall ab: antworten, zuweisen, Zeiten erfassen, sicher im Team chatten. Ein unabhängiger, inoffizieller Client für Ihren Zammad-Server.
```

**Keywords (100)**
```
ticket,support,servicedesk,itsm,itil,warteschlange,kunde,störung,anfrage,tickets,agent
```

**Beschreibung (4000)**
```
Verwalten Sie Ihren Zammad-Helpdesk direkt vom iPhone, iPad und von der Apple Watch aus. Nehmen Sie ein Ticket aus der Warteschlange, antworten Sie einem Kunden, erfassen Sie Ihre Zeit und übergeben Sie Arbeit an Kolleginnen und Kollegen — ohne den Laptop aufzuklappen.

BITTE BEACHTEN: Dies ist ein unabhängiger, inoffizieller Client für Zammad. Die App wird nicht von der Zammad GmbH entwickelt, herausgegeben, unterstützt oder empfohlen. Sie benötigen einen eigenen Zammad-Server und ein Agenten-Konto. „Zammad“ ist eine Marke des jeweiligen Inhabers.

IHRE WARTESCHLANGE, ÜBERALL
• Meine Tickets, nicht zugewiesene und alle offenen Tickets mit einem Tippen
• Nach Status filtern und die gesamte Warteschlange durchsuchen
• Ungelesen-Markierungen, damit Sie sofort sehen, was sich geändert hat
• Vollständiger Gesprächsverlauf mit formatierten Artikeln und Anhängen

ANTWORTEN UND ERLEDIGEN
• Öffentliche Antworten oder interne Notizen, mit Fotos und Dateien
• Neue Tickets anlegen — mit Kundensuche, Gruppe, Typ und Tags
• Status, Priorität, Besitzer und Wartezeit ändern
• Ein Ticket mit einer Notiz übergeben — Zammad benachrichtigt die Kollegin oder den Kollegen
• Aufgewendete Zeit auf Ihre Zammad-Aktivitäten buchen

TEAM-CHAT, ENDE-ZU-ENDE-VERSCHLÜSSELT
• Einzel- und Gruppenchats mit Kolleginnen und Kollegen
• Auf ein Ticket verweisen, damit alle den Kontext haben
• Dateien und Fotos senden
• Nachrichten werden auf Ihrem Gerät verschlüsselt und sind nur für die Empfänger lesbar
• Aufbewahrungsdauer selbst wählen — von 30 Tagen bis unbegrenzt

IMMER AUF DEM LAUFENDEN
• Push-Benachrichtigungen in Echtzeit bei neuen und geänderten Tickets
• Auf eine Mitteilung tippen und direkt im Ticket landen
• Kennzeichen am App-Symbol für alles, was noch offen ist
• Die Hintergrundaktualisierung hält die Warteschlange aktuell

FÜR IHREN ARBEITSALLTAG GEBAUT
• Geführte Einrichtung: API-Token oder Single Sign-on, mit Verbindungstest
• Face ID / Touch ID-Sperre für die gesamte App
• Helles und dunkles Design, 14 Hintergründe und 18 Chat-Designs
• Apple Watch-App für den schnellen Blick auf die Warteschlange
• Verfügbar auf Deutsch, Englisch, Niederländisch und Französisch

DATENSCHUTZ UND SICHERHEIT
Ihre Tickets bleiben zwischen Ihrem Gerät und Ihrem eigenen Zammad-Server — kein Konto, keine Zwischenstation für Ihre Helpdesk-Daten. Ihr API-Token wird auf dem Gerät gespeichert. Chat-Nachrichten sind Ende-zu-Ende-verschlüsselt, sodass der zustellende Server ausschließlich verschlüsselten Text sieht.

KOSTENLOS, MIT OPTIONALER FREISCHALTUNG
Die App ist kostenlos und werbefinanziert. Die einmalige Lifetime-Freischaltung entfernt alle Werbung, aktiviert Echtzeit-Benachrichtigungen samt Symbolkennzeichen und unterstützt die Weiterentwicklung. Kein Abo, keine wiederkehrenden Kosten.

VORAUSSETZUNGEN
• Eine erreichbare Zammad-Installation (selbst gehostet oder Cloud)
• Ein Agenten-Konto und ein API-Token mit mindestens ticket.agent-Rechten
• Für Echtzeit-Benachrichtigungen ein Webhook in Zammad — die App enthält eine Schritt-für-Schritt-Anleitung

KEINE VERBINDUNG ZUR ZAMMAD GMBH
Diese App ist ein unabhängig entwickeltes Produkt eines Drittanbieters. Sie steht in keiner Verbindung zur Zammad GmbH und wird von dieser weder autorisiert noch unterstützt. Bei Fragen zur App wenden Sie sich bitte an uns — nicht an Zammad. Bei Fragen zu Ihrem Zammad-Server wenden Sie sich an Ihre Administration.
```

**Neue Funktionen (1.2)**
```
• Ende-zu-Ende-verschlüsselter Team-Chat — einzeln und in Gruppen, mit Ticketbezug, Anhängen und 18 Chat-Designs
• Tickets mit einer Notiz direkt aus dem Ticket an Kolleginnen und Kollegen übergeben
• Verschlüsselungsanzeige, damit Sie jederzeit sehen, dass eine Nachricht geschützt ist
• Neue Hintergründe und eine Hintergrundauswahl für helles und dunkles Design
• Zuverlässigere Zustellung von Push-Benachrichtigungen und schnelleres Laden

Danke, dass Sie die App nutzen. Über Rückmeldungen und Fehlerberichte freuen wir uns.
```

---

### 7.3 Français (fr-FR)

**Nom (30)**
```
Helpdesk pour Zammad
```

**Sous-titre (30)**
```
Client mobile non officiel
```

**Texte promotionnel (170)**
```
Traitez votre file partout : répondre, réattribuer, saisir votre temps, discuter en toute sécurité. Un client indépendant et non officiel pour votre serveur Zammad.
```

**Mots-clés (100)**
```
ticket,support,servicedesk,itsm,itil,assistance,client,incident,demande,file,tickets,agent
```

**Description (4000)**
```
Gérez votre helpdesk Zammad directement depuis votre iPhone, votre iPad et votre Apple Watch. Prenez un ticket dans la file, répondez à un client, enregistrez votre temps et transmettez le travail à un collègue — sans ouvrir votre ordinateur.

À NOTER : il s'agit d'un client indépendant et non officiel pour Zammad. Cette application n'est ni développée, ni publiée, ni approuvée, ni prise en charge par Zammad GmbH. Vous devez disposer de votre propre serveur Zammad et d'un compte agent. « Zammad » est une marque de son propriétaire respectif.

VOTRE FILE, OÙ QUE VOUS SOYEZ
• Mes tickets, tickets non attribués et tous les tickets ouverts en un geste
• Filtrez par statut et recherchez dans toute votre file
• Marqueurs de non-lu pour repérer d'un coup d'œil ce qui a changé
• Historique complet des échanges, avec mise en forme et pièces jointes

RÉPONDRE ET RÉSOUDRE
• Réponses publiques ou notes internes, avec photos et fichiers
• Créez des tickets avec recherche de client, groupe, type et étiquettes
• Modifiez le statut, la priorité, le propriétaire et le délai d'attente
• Transmettez un ticket à un collègue avec un mot — Zammad le prévient
• Enregistrez le temps passé sur vos activités Zammad

MESSAGERIE D'ÉQUIPE CHIFFRÉE DE BOUT EN BOUT
• Discutez avec vos collègues en tête-à-tête ou en groupe
• Référencez un ticket pour que chacun ait le contexte
• Envoyez des fichiers et des photos
• Les messages sont chiffrés sur votre appareil et lisibles uniquement par les destinataires
• Choisissez la durée de conservation, de 30 jours à illimitée

RESTEZ INFORMÉ
• Notifications push en temps réel à la création ou à la mise à jour d'un ticket
• Touchez une notification pour ouvrir directement le ticket concerné
• Pastille sur l'icône pour ce qui attend encore votre intervention
• L'actualisation en arrière-plan garde votre file à jour

PENSÉE POUR VOTRE FAÇON DE TRAVAILLER
• Assistant de configuration : jeton d'API ou authentification unique, avec test de connexion
• Verrouillage de l'application par Face ID / Touch ID
• Thèmes clair et sombre, 14 fonds d'écran et 18 thèmes de discussion
• Application Apple Watch pour un coup d'œil sur votre file
• Disponible en français, anglais, néerlandais et allemand

CONFIDENTIALITÉ ET SÉCURITÉ
Vos tickets restent entre votre appareil et votre propre serveur Zammad : aucun compte à créer, aucun intermédiaire sur vos données. Votre jeton d'API est conservé sur votre appareil. Les messages sont chiffrés de bout en bout : le serveur qui les achemine ne détient que du texte chiffré.

GRATUIT, AVEC UN DÉBLOCAGE FACULTATIF
L'application est gratuite et financée par la publicité. Le déblocage à vie, en un seul achat, supprime toute publicité, active les notifications en temps réel et la pastille, et soutient le développement. Sans abonnement ni frais récurrents.

CONFIGURATION REQUISE
• Une installation Zammad accessible (auto-hébergée ou dans le cloud)
• Un compte agent et un jeton d'API disposant au minimum des droits ticket.agent
• Pour les notifications en temps réel, un webhook à configurer dans Zammad — un guide pas à pas est inclus

AUCUN LIEN AVEC ZAMMAD GMBH
Cette application est un produit tiers développé de façon indépendante. Elle n'est ni affiliée à Zammad GmbH, ni autorisée ou prise en charge par cette société. Pour toute question sur l'application, contactez-nous — pas Zammad. Pour toute question sur votre serveur Zammad, adressez-vous à votre administrateur.
```

**Nouveautés (1.2)**
```
• Messagerie d'équipe chiffrée de bout en bout — en tête-à-tête ou en groupe, avec références de tickets, pièces jointes et 18 thèmes
• Transmettez un ticket à un collègue avec un mot, directement depuis le ticket
• Indicateur de chiffrement, pour savoir en permanence qu'un message est protégé
• Nouveaux fonds d'écran et sélecteur de fond pour les modes clair et sombre
• Fiabilité accrue des notifications push et chargement plus rapide des tickets

Merci d'utiliser l'application. Vos retours et signalements de bugs sont les bienvenus.
```

---

## 8. App Review Notes (App Store Connect → App Review Information)

Reviewers cannot test this app without a server, so give them one. A submission without
working credentials will be rejected as "unable to review".

```
This is an independent, unofficial third-party client for Zammad, an open-source helpdesk
system. It is not published by or affiliated with Zammad GmbH, and the description states
this clearly. The app connects only to a Zammad server that the user supplies.

DEMO ACCOUNT
A test Zammad instance with sample tickets is ready for review:
  Server URL: https://zammaddemo.world-ict.nl
  API token:  <paste the reviewer token — kept out of this repo on purpose>
In the setup wizard, choose "API token", paste the URL and token, and tap Test Connection.
Sample tickets, customers and chat contacts are pre-loaded.
(Web login for the same agent, should the reviewer ask: reviewer@zammaddemo.world-ict.nl)

PUSH NOTIFICATIONS
Zammad has no native APNS support, so notifications are relayed by our own proxy at
zammadproxy.world-ict.nl. Zammad calls a per-user webhook on the proxy, and the proxy
sends an APNS push. The proxy stores the device token and a user identifier; ticket
content is not stored.

CHAT ENCRYPTION
Agent-to-agent chat is end-to-end encrypted with Apple CryptoKit (Curve25519 key agreement
+ ChaChaPoly). The relay only ever stores ciphertext.

IN-APP PURCHASE
"Lifetime Unlock" (com.baseonline.zammadmobile.premium.lifetime) is a one-time
non-consumable that removes ads and enables real-time notifications and the icon badge.
It can be tested in the sandbox; Restore Purchases is in Settings.

TRADEMARK
The app is named "Helpdesk for Zammad". The Zammad name is used only descriptively, in
the "for" form, to identify the system this client works with. The description states in
its second paragraph that the app is unofficial and unaffiliated.
```

---

## 8b. Reply to "Guideline 2.1 — Information Needed" (9 Sept 2026)

App Review asked for six things on the first 1.2 submission (build 1.2 (40),
Xcode Cloud). Paste the text below as the reply in App Store Connect **and**
append it to the Notes field of App Review Information, as they ask. Attach
the screen recording to the reply (see the recording plan after the text).

```
Thank you for reviewing Helpdesk for Zammad. Answers to your six points:

1. SCREEN RECORDING
Attached: recorded on a physical iPhone running the current iOS release. It
starts at app launch and shows: the setup wizard (server URL + API token, Test
Connection), the ticket queue and filters, opening a ticket, replying, handing
a ticket to a colleague, the encrypted colleague chat (sending, deleting a
message, deleting a conversation, leaving/deleting a group), the Premium
paywall with the three products and a sandbox purchase of Lifetime Unlock, and
finally Settings > Disconnect, which removes all stored credentials from the
device.

Account registration / deletion: the app does not create accounts. Users sign
in with an existing account on their own Zammad server (self-hosted helpdesk
software), using an API token issued there. There is nothing to register and
therefore nothing to delete; "Disconnect" in Settings wipes the device's copy of
the credentials, and disabling notifications removes the push registration on
our relay immediately.

User-generated content: the only user content is the colleague chat. It is a
closed channel between authenticated agents of the same Zammad server — the
customer's own organisation — not a public or cross-organisation space.
Members are administered by that organisation's Zammad admin, who can
deactivate any agent, which removes them from the chat directory. Every user
can delete their own messages for everyone, delete a whole conversation for
both sides, and leave a group. Contact for abuse reports is in the app and in
the support page (b.jonkers@world-ict.nl).

Paid content: Premium (Lifetime Unlock, or a monthly/yearly subscription)
removes the ad banner and enables real-time push notifications and the app
icon badge. All three products are shown and the sandbox purchase is in the
recording.

2. PURPOSE AND AUDIENCE
Helpdesk for Zammad is an independent mobile client for Zammad, an open-source
helpdesk / ticketing system that companies run on their own servers. Its users
are support agents and IT staff of such companies. Zammad's own web interface
is built for desktop; this app lets an agent work the ticket queue from a
phone or Apple Watch: triage, reply, reassign, log time, and get a push
notification when a ticket they own changes. It solves the "I'm away from my
desk and a ticket escalated" problem.

3. SETUP AND ACCESS
A demo Zammad server with sample data is ready for you:
  Server URL: https://zammaddemo.world-ict.nl
  API token:  <the token in App Review Information>
In the setup wizard choose "API token", enter the URL and the token, tap Test
Connection. The queue shows nine tickets across new / open / pending / closed;
some are assigned to you (App Reviewer), some to a colleague (Demo Colleague),
some unassigned. "Demo Colleague" is available in the chat and as a hand-off
target. Web login for the same account, should you want to see the server
side: reviewer@zammaddemo.world-ict.nl / <password in App Review Information>.

Push notifications need a webhook trigger on the Zammad server; the app shows
the exact URL to paste. On the demo server this is already configured for the
reviewer account.

4. EXTERNAL SERVICES
- The user's own Zammad server (self-hosted by the customer), via Zammad's
  public REST API. This is where all ticket data lives; we never see it.
- Our relay at zammadproxy.world-ict.nl, operated by us: forwards Zammad
  webhook events to Apple Push Notification service, and relays the
  end-to-end-encrypted colleague chat (it stores ciphertext only).
- Apple Push Notification service, StoreKit (In-App Purchase).
- Google AdMob (banner ad in the free version) with Google's User Messaging
  Platform for consent where required.
No authentication providers, payment processors of our own, AI services, or
analytics SDKs.

5. REGIONAL DIFFERENCES
The app functions identically in all regions. Two cosmetic differences: the ad
consent form appears only where the law requires it (EEA/UK), and the interface
follows the device language for English, Dutch, German and French. Ad fill may
vary by region; the app hides the banner when no ad is available.

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not a regulated industry. Zammad is open-source server software (AGPL) with a
public REST API intended for third-party clients; no license or credential is
required to build a client for it. The name "Zammad" is used only descriptively
("Helpdesk for Zammad") to identify what the app connects to, and the App Store
description states that the app is independent and not affiliated with Zammad
GmbH. The app contains no protected third-party material.
```

### Recording plan (2–4 minutes, one take, physical iPhone)

Use iOS screen recording (Control Center). Use the *demo* server and the
reviewer token so what they see in the video matches what they get. Order:

1. Launch from the home screen (this must be the first frame).
2. Setup wizard: server URL, API token, Test Connection, queue loads.
3. Filters (Mine / Unassigned / All open), open a ticket, scroll the thread.
4. Reply to the ticket; log time.
5. Hand off the ticket to Demo Colleague with a note.
6. Chat: open the conversation with Demo Colleague, send a message, delete it
   ("Message deleted"), then delete the conversation. Open a group, leave it.
7. Settings: Premium — show the three products, buy Lifetime Unlock with a
   sandbox tester account (free); banner disappears, notifications toggle
   becomes available. Show Restore Purchases.
8. Settings: Disconnect, back to the wizard. Stop recording.

**Afterwards:** wipe the chat conversation with the curl in
`demo-server/README.md`. The reviewer's device does not exist yet, so the
messages you sent in the recording would be unreadable on it.

The 8-second clip in `Screenshots/` is an App Preview draft, not this.

## 9. Screenshots and app preview

### What is in `Screenshots/`

Seven PNGs captured on an iPhone 17 Pro at 1206 × 2622, plus a screen recording that is
not being used (see below). **Neither the screenshots' size nor their alpha channel is
accepted by App Store Connect**, so the originals cannot be uploaded as they are.

Accepted iPhone screenshot sizes are 1260 × 2736, 1290 × 2796 or 1320 × 2868 (the 6.9"
slot) and 1284 × 2778 or 1242 × 2688 (6.5"). The iPhone 17 Pro is a 6.3" device and has no
slot of its own. Separately, screenshots may not contain alpha or transparency, and every
original does.

### Ready to upload: `Screenshots/AppStore/iPhone-6.9/`

Converted copies at **1260 × 2736, alpha flattened**, numbered in the order they should
appear on the product page. 1260 × 2736 was chosen because it is the accepted size closest
to the source: a 4.5% upscale, against 9.5% for 1320 × 2868, and the aspect ratio differs
by 0.1% so nothing is stretched. Originals are untouched.

| # | File | Screen | Caption | Notes |
| --- | --- | --- | --- | --- |
| 1 | `01-queue.png` | My Assigned Tickets | Your whole queue, in your pocket | **Re-shoot.** One ticket in the list; the wallpaper fills three quarters of the frame. Your most important screenshot currently makes the app look empty. |
| 2 | `02-ticket-detail.png` | Ticket detail, light | Every detail, one tap away | Good. Populated and legible. |
| 3 | `03-encrypted-chat.png` | Chat conversation | Encrypted chat with your team | **Your best asset.** Padlocks, a ticket reference and a real conversation — this is the feature no other client has. Consider leading with it. |
| 4 | `04-edit-ticket.png` | Edit Ticket | Change status, priority, owner | Good. |
| 5 | `05-reply.png` | Reply composer | Reply without opening a laptop | **Re-shoot.** Shows a raw quoted email full of `>` markers, mixing Dutch and English. Compose a short clean reply instead. |
| 6 | `06-handoff.png` | Hand off ticket | Hand off a ticket in seconds | **Re-shoot.** Empty form, "Select engineer" unset. Fill in a colleague and a message. |
| 7 | `07-time-accounting.png` | Add Spent Time | Log time as you work | **Re-shoot.** Empty form; roughly 70% of the frame is black. Enter an activity and a value. |

Captions are burned into the image above the device frame, ten words or fewer. Order
matters — most people never scroll past the first two.

**Better than converting: re-capture.** Run the app on an iPhone 17 Pro Max simulator and
you get 1320 × 2868 natively, with no upscaling and no alpha. If you re-shoot the four
weak frames anyway, do the whole set that way and replace this folder.

### iPad — `Screenshots/AppStore/iPad-13/`

Captured on an iPad Air 13" (M4) at **2048 × 2732, an accepted 13" size**, so only the
alpha channel needed flattening. Six of the eight originals are included; the other two are
held back.

| # | File | Screen | Caption | Notes |
| --- | --- | --- | --- | --- |
| 1 | `01-queue.png` | My Assigned Tickets | Your whole queue, on the big screen | **Re-shoot.** One ticket, and the flower wallpaper fills roughly 85% of a 13" screen. Worse here than on iPhone. |
| 2 | `02-ticket-detail.png` | Ticket detail | Every detail, one tap away | Usable. Busy wallpaper behind the translucent panels. |
| 3 | `03-reply.png` | Reply | Reply without opening a laptop | Better than the iPhone version — has real typed text ("I'll fix it for you."). |
| 4 | `04-edit-ticket.png` | Edit Ticket | Change status, priority, owner | Good. |
| 5 | `05-handoff.png` | Hand off ticket | Hand off a ticket in seconds | Message filled in, but "Select engineer" is still unset. Pick a colleague and re-shoot. |
| 6 | `06-new-ticket.png` | New Ticket | Raise a ticket from anywhere | Good. |

**Excluded — do not upload:**

- *Server Configuration* (11.04.45) — the setup wizard with empty fields. A configuration
  screen shows nothing of what the app does, and setup/login screens make poor first
  impressions on a product page.
- *Chat* (11.08.27) — **this one matters.** Almost every bubble reads "🔒 Encrypted
  message" because the iPad cannot decrypt history encrypted for the iPhone's key. As a
  marketing image it reads as "this app cannot show your messages". See the note below.

### Apple Watch — `Screenshots/AppStore/Watch/`

**416 × 496 (Series 11)**, an accepted size. Only one of the three originals is usable, and
one screenshot satisfies the requirement.

| # | File | Screen | Notes |
| --- | --- | --- | --- |
| 1 | `01-ticket-list.png` | Tickets | Usable. Shows real inbox subjects and Dutch relative dates — see the language note. |

**Excluded:** the 11.20.52 capture is the loading spinner on a black screen, and 11.22.07
was taken mid-transition with the Status row cut off at the bottom edge.

Whichever Watch size you choose, use that same size for every localization — Apple requires
it to be consistent across languages.

### Two content issues that run through the whole set

**Mixed languages.** These are your English screenshots, but they show Dutch strings coming
from the server and the system: the status badge reads "In behandeling", the Watch list
says "1 maand geleden" and "2 maanden gel…", the Watch detail labels the customer "Klant",
and several ticket bodies are Dutch. Some of that is your Zammad instance's data rather
than the app, but a reviewer or customer sees one inconsistent screen. For the English
listing, capture against English ticket data with the device language set to English.

**The iPad chat screenshot was the one-key-per-user limitation — now fixed.** Chat has
moved to per-device keys (protocol v4): each install publishes its own key and its own push
registration, a direct message body is sealed with a random key wrapped for every device of
both sides, and group keys are re-wrapped for devices that join later. An agent can now run
the app on an iPhone and an iPad at once, with both readable and both getting pushes.

**Deploy order matters.** The updated `proxy/` must be live *before* the app ships — a v4
client sends key envelopes an older proxy would drop, producing messages nobody can read.
Once the proxy is deployed, re-take the iPad chat screenshot: it should show real message
text rather than a column of "🔒 Encrypted message".

### App preview video — not submitting one

**Decision: version 1.2 ships with screenshots only.** App previews are optional, and the
existing recording (`Screen Recording iPhone 17 Pro 07-09-2026 at 09.20.58.mp4`) would have
needed a full re-record — at 7.6 seconds it falls short of Apple's 15-second minimum, which
is the one requirement that cannot be fixed in post.

Leave the file in `Screenshots/` or delete it; it is not referenced by the submission. If
you want a preview in a later release, re-record 15-30 seconds and transcode to 886 × 1920,
30 fps, H.264 High Profile Level 4.0 at 10-12 Mbps.

---

## 10. Store metadata checklist

| Field | Value |
| --- | --- |
| Primary category | Productivity |
| Secondary category | Business |
| Age rating | 4+ |
| Price | Free, with In-App Purchase |
| In-App Purchase | Lifetime Unlock — one-time, non-consumable |
| Copyright | 2026 World ICT |
| Support URL | `https://base1983.github.io/Zammad-Helpdesk/` — `docs/index.html`, served by GitHub Pages from `main`/`docs`; same URL in all four localisations |
| Marketing URL | optional |
| Privacy Policy URL | `https://base1983.github.io/Zammad-Helpdesk/privacy.html` — `docs/privacy.html`; lives under App Information, not on the version page |

---

## 11. Before you hit Submit

Real issues found in the project that affect this submission:

1. ~~**Privacy manifest is missing.**~~ **Done.** `PrivacyInfo.xcprivacy` is now in both
   `Zammad Helpdesk/` and `Zammad Helpdesk Watch App/`. Both source folders are Xcode 16
   synchronized groups, so no project-file changes were needed; a simulator build confirms
   each manifest lands at the top level of its bundle. The watch app needed its own because
   its target compiles `Managers/Managers.swift`, which uses `UserDefaults`.

   **Declared required-reason API:** `NSPrivacyAccessedAPICategoryUserDefaults` with reasons
   `CA92.1` (app-only defaults, as in ReadStatusManager) and `1C8F.1` (the
   `group.com.World-ICT.Zammad-Helpdesk` app-group suite used everywhere else).

   **Declared data collection (iOS app), all "App Functionality", all linked to the user,
   none used for tracking** — this is what leaves the device for the notification/chat
   proxy, so your App Privacy nutrition labels must match it:

   | Type | What it actually is |
   | --- | --- |
   | Name | Agent display name, sent when registering for chat |
   | Email Address | Agent email, sent when registering for chat |
   | User ID | The proxy user UUID generated on first registration |
   | Device ID | The APNS device token |
   | Other User Content | Chat messages and attachments — ciphertext only |
   | Other Data Types | Zammad server URL and API token, so the proxy can poll on your behalf |

   The watch manifest declares no collection: it talks only to the user's own Zammad server.

   Two things to sanity-check against your proxy's actual behaviour before submitting.
   First, the proxy stores the **Zammad API token** — that is a credential held on your
   server, and your privacy policy needs to say so plainly. Second, `NSPrivacyTracking` is
   `false` at app level, which is correct because your own code does no tracking; the
   AdMob and UserMessagingPlatform frameworks ship their own manifests declaring theirs,
   and Apple merges all of them into the privacy report.

2. **Export compliance answer needs a second look.**
   `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is set, but the app now does
   end-to-end encrypted messaging. Standard published algorithms via Apple's frameworks
   usually qualify for the exemption, so `NO` is defensible — but since encryption is now
   a headline feature rather than incidental, confirm the answer (and whether you owe a
   self-classification report) before submitting. This is a legal/compliance call, not a
   code one.

3. ~~**SKAdNetwork list is one entry long.**~~ **Done.** It now carries Google's full
   list of 50 identifiers. It was also written as an array of plain strings instead of
   dicts keyed by `SKAdNetworkIdentifier`, so even the single entry it had was inert; the
   format is fixed too. Verified in a Release archive: 50 items in the built bundle.

4. **App Privacy nutrition labels.** You must declare what AdMob collects (device ID,
   usage data, coarse location, "used for third-party advertising"), plus the identifiers
   your notification proxy stores. Getting this wrong is the most common cause of a
   post-approval takedown.

5. **No ATT prompt is implemented.** That is a valid choice — AdMob will serve
   non-personalised ads. Just make sure the nutrition labels say "not linked to you"
   consistently with that, and do not add `NSUserTrackingUsageDescription` unless you
   actually present the prompt.

6. ~~**No consent flow (CMP).**~~ **Done.** `AdConsentManager` now drives Google's User
   Messaging Platform: it requests the consent status, presents the form where one is
   required, and starts the Mobile Ads SDK only afterwards; the banner waits on
   `canRequestAds`. Settings shows a lasting entry point to change that choice, exactly
   when UMP reports `privacyOptionsRequirementStatus == .required`, and never to premium
   users. This is Google's EEA policy requirement, not Apple's.

7. ~~**Ads used Google's test unit.**~~ **Done.** Release builds serve
   `ca-app-pub-7428603098298858/7003691655`; Debug keeps the test unit, so development
   never clicks live ads.

8. ~~**Watch app version mismatch.**~~ **Done.** The embedded watch app was on 1.1
   (build 3) against the iOS app's 1.2 — confirmed in an actual archive, and it would
   have failed upload validation. Both are 1.2, build 10011.

9. ~~**App Review could not test the purchase.**~~ **Done.** Premium used to be granted
   automatically whenever `AppTransaction.environment != .production`, and App Review runs
   in the same sandbox environment as TestFlight, so the reviewer would have received every
   paid feature for free and never seen the paywall. Entitlement now comes only from the
   lifetime unlock or an active subscription. Sandbox purchases are free, so TestFlight
   testers still unlock everything through the real flow — which is what the review note
   above asks the reviewer to do.

10. ~~**Still yours to fill in: the demo account.**~~ **Live.** `demo-server/` set up
    `https://zammaddemo.world-ict.nl` on web05 (Zammad + PostgreSQL + Redis +
    Elasticsearch 9, behind Plesk's nginx) and `seed-demo.sh` loaded it: two agents
    ("App Reviewer", "Demo Colleague"), an organisation, three customers, eight tickets
    across new/open/pending/closed with owners spread over both agents and unassigned, and
    the reviewer's API token with `ticket.agent`. The token is deliberately not in this
    file — paste it into App Store Connect from wherever you keep it. Still to do before
    submitting: sign "Demo Colleague" into the app from your own phone once, so the
    reviewer has a chat contact (see `demo-server/README.md`). The instance has to stay
    reachable for the whole review; `systemctl status zammad` on web05 is the check.

11. **Disclaimer placement.** Keep the unofficial notice in the *second paragraph* of the
   description, not buried at the bottom. The App Store truncates after roughly three
   lines on the product page, but reviewers read the whole field — having it high up is
   what defuses a 5.2.1 question before it is asked.
