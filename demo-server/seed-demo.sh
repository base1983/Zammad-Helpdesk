#!/usr/bin/env bash
# seed-demo.sh — load the App Review demo data into the Zammad demo instance
# and mint the reviewer's API token.
#
#   ZAMMAD_URL=https://zammaddemo.world-ict.nl \
#   ADMIN_USER=admin@example.com ADMIN_PASS='...' \
#   REVIEW_PASS='...' ./seed-demo.sh
#
# Creates, through the REST API (idempotent — re-running skips what exists):
#   - an organisation and three customers
#   - two agents: "App Reviewer" (the account in the review notes) and
#     "Demo Colleague" (so handoff and chat have someone to talk to)
#   - eight tickets in a mix of states, with a short conversation each
#   - an API token with the ticket.agent permission for the reviewer
#
# Runs from anywhere with curl + python3; needs no shell on the server.

set -euo pipefail

ZAMMAD_URL="${ZAMMAD_URL:-https://zammaddemo.world-ict.nl}"
ADMIN_USER="${ADMIN_USER:?set ADMIN_USER (the admin login from the getting-started wizard)}"
ADMIN_PASS="${ADMIN_PASS:?set ADMIN_PASS}"
REVIEW_PASS="${REVIEW_PASS:?set REVIEW_PASS (password for the App Reviewer agent)}"
REVIEW_EMAIL="${REVIEW_EMAIL:-reviewer@zammaddemo.world-ict.nl}"
COLLEAGUE_EMAIL="${COLLEAGUE_EMAIL:-colleague@zammaddemo.world-ict.nl}"

api() { # method path [json]
    local method="$1" path="$2" body="${3:-}"
    # Retries cover the occasional connection timeout or transient 5xx a
    # freshly installed instance produces while Elasticsearch settles.
    curl -fsS --connect-timeout 10 -m 60 --retry 3 --retry-delay 3 --retry-all-errors \
        -u "${ADMIN_USER}:${ADMIN_PASS}" -X "$method" \
        -H 'Content-Type: application/json' \
        ${body:+--data "$body"} \
        "${ZAMMAD_URL}/api/v1${path}"
}

json() { python3 -c "import json,sys; print(json.dumps(${1}))"; }
field() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

echo "==> Organisation"
ORG_ID=$(api GET "/organizations/search?query=name:%22Acme%20Logistics%22" | field 'd[0]["id"] if d else ""')
if [[ -z "$ORG_ID" ]]; then
    ORG_ID=$(api POST /organizations "$(json '{"name":"Acme Logistics","domain":"acme-logistics.example","note":"Demo customer organisation"}')" | field 'd["id"]')
fi
echo "    organisation id ${ORG_ID}"

make_user() { # email firstname lastname roles-json extra-json
    local email="$1" first="$2" last="$3" roles="$4" extra="${5:-}"
    local id
    id=$(api GET "/users?per_page=500" | field "next((u['id'] for u in d if (u.get('email') or '').lower() == '${email}'.lower()), '')")
    if [[ -z "$id" ]]; then
        id=$(api POST /users "{\"email\":\"${email}\",\"firstname\":\"${first}\",\"lastname\":\"${last}\",\"roles\":${roles},\"active\":true${extra:+,${extra}}}" | field 'd["id"]')
        echo "    created ${first} ${last} (${id})"
    else
        echo "    exists  ${first} ${last} (${id})"
    fi
    echo "$id"
}

GROUP_ID=$(api GET /groups | field 'next(g["id"] for g in d if g["active"])')

echo "==> Agents"
REVIEWER_ID=$(make_user "$REVIEW_EMAIL" "App" "Reviewer" '["Agent"]' "\"password\":\"${REVIEW_PASS}\"" | tail -1)
COLLEAGUE_ID=$(make_user "$COLLEAGUE_EMAIL" "Demo" "Colleague" '["Agent"]' "\"password\":\"${REVIEW_PASS}\"" | tail -1)
# The Agent role alone grants no group access, and Zammad refuses to assign a
# ticket to an agent outside its group ("Invalid value for field owner_id").
# Applied on every run, so agents created earlier get it too.
for agent in "$REVIEWER_ID" "$COLLEAGUE_ID"; do
    api PUT "/users/${agent}" "{\"group_ids\":{\"${GROUP_ID}\":[\"full\"]}}" >/dev/null
done
echo "    both agents have full access to group ${GROUP_ID}"

echo "==> Customers"
C1=$(make_user "j.devries@acme-logistics.example" "Jan" "de Vries" '["Customer"]' "\"organization_id\":${ORG_ID}" | tail -1)
C2=$(make_user "s.bakker@acme-logistics.example" "Sanne" "Bakker" '["Customer"]' "\"organization_id\":${ORG_ID}" | tail -1)
C3=$(make_user "m.smit@example.org" "Mark" "Smit" '["Customer"]' | tail -1)

echo "==> Tickets"
make_ticket() { # title customer_id state priority owner_id body followup
    local title="$1" cust="$2" state="$3" prio="$4" owner="$5" body="$6" followup="${7:-}"
    if api GET "/tickets?per_page=500" | field "any(t['title'] == '''${title}''' for t in d)" | grep -q True; then
        echo "    exists  ${title}"; return
    fi
    local owner_json=""
    [[ -n "$owner" ]] && owner_json=",\"owner_id\":${owner}"
    # Pending states are refused without a pending_time ("Missing required
    # value for field 'pending_time'"). Tomorrow, same hour, is fine for a demo.
    local pending_json=""
    if [[ "$state" == pending* ]]; then
        pending_json=",\"pending_time\":\"$(date -u -v+1d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '+1 day' '+%Y-%m-%dT%H:%M:%SZ')\""
    fi
    local id
    id=$(api POST /tickets "{\"title\":\"${title}\",\"group_id\":${GROUP_ID},\"customer_id\":${cust},\"state\":\"${state}\",\"priority\":\"${prio}\"${owner_json}${pending_json},\"article\":{\"subject\":\"${title}\",\"body\":\"${body}\",\"type\":\"web\",\"internal\":false,\"sender\":\"Customer\"}}" | field 'd["id"]')
    if [[ -n "$followup" ]]; then
        api POST /ticket_articles "{\"ticket_id\":${id},\"body\":\"${followup}\",\"type\":\"note\",\"internal\":false,\"sender\":\"Agent\"}" >/dev/null
    fi
    echo "    created ${title} (#${id})"
}

make_ticket "Scanner in warehouse 2 no longer pairs" "$C1" new "2 normal" "" \
    "Since this morning the Zebra scanner in warehouse 2 refuses to pair with the terminal. Rebooted both, no change."
make_ticket "Invoice PDF shows wrong VAT number" "$C2" open "3 high" "$REVIEWER_ID" \
    "The VAT number on invoice 2026-0412 is our old one. Can you regenerate it?" \
    "Looking into it — the template still has the old number. Will push a fix today."
make_ticket "Request: extra user licence for planning team" "$C2" open "1 low" "$REVIEWER_ID" \
    "We are adding two planners next month and need two more seats."
make_ticket "VPN drops every 20 minutes on the Utrecht site" "$C1" open "3 high" "$COLLEAGUE_ID" \
    "The site-to-site VPN reconnects about every 20 minutes. Logs attached on request." \
    "Seeing the same in the firewall logs — looks like a DPD timeout. Adjusting now."
make_ticket "Password reset for m.smit" "$C3" closed "2 normal" "$REVIEWER_ID" \
    "Locked out after too many attempts, please reset." \
    "Reset done, temporary password sent by SMS."
make_ticket "Printer on floor 3 prints blank pages" "$C3" pending\ reminder "2 normal" "$REVIEWER_ID" \
    "Every page comes out blank since the toner swap." \
    "Please try reseating the drum unit; I will check back tomorrow."
make_ticket "Slow ticket list in the mobile app" "$C1" new "2 normal" "" \
    "The queue takes ~10s to load on 4G. Is that expected?"
make_ticket "Onboarding checklist for new hire (starts Monday)" "$C2" open "2 normal" "" \
    "New colleague starts Monday: laptop, mail, VPN, badge."

echo "==> Reviewer API token (ticket.agent)"
# A token can only be minted by its own user, so this call authenticates as
# the reviewer rather than the admin.
TOKEN=$(curl -fsS --connect-timeout 10 -m 60 --retry 3 --retry-delay 3 --retry-all-errors \
    -u "${REVIEW_EMAIL}:${REVIEW_PASS}" -X POST \
    -H 'Content-Type: application/json' \
    --data '{"name":"App Review (iOS app)","permission":["ticket.agent","user_preferences"],"expires_at":null}' \
    "${ZAMMAD_URL}/api/v1/user_access_token" | field 'd["token"]')

cat <<EOF

Done. Paste into APP_STORE_LISTING.md section 8 (App Review Notes):

  Server URL: ${ZAMMAD_URL}
  API token:  ${TOKEN}
  (login for the web UI, if asked: ${REVIEW_EMAIL} / the REVIEW_PASS you set)

Then, from your own phone, sign the "Demo Colleague" agent into the app once
(${COLLEAGUE_EMAIL} / same password, or mint a token the same way) so the
reviewer has a chat contact to hand a ticket to — chat contacts only appear
after an agent has opened the app on that instance.
EOF
