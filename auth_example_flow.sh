#!/bin/bash

CODE_REQUEST_RESPONSE=$(curl --silent --proto '=https' --tlsv1.2  --request POST \
      --url "https://internal-portal.us.auth0.com/oauth/device/code" \
      --header 'content-type: application/x-www-form-urlencoded' \
      --data "client_id=STAayma6q8MaHQ1sTOBMNgOzqiq6nomD" \
      --data scope='read:current_user offline_access' \
      --data audience="https://iportal.symbiont.io")

DEVICE_CODE=`echo ${CODE_REQUEST_RESPONSE} | jq .device_code | tr -d \"`
USER_CODE=`echo ${CODE_REQUEST_RESPONSE} | jq .user_code | tr -d \"`
VERIFICATION_URL=`echo ${CODE_REQUEST_RESPONSE} | jq .verification_uri_complete | tr -d \"`

open ${VERIFICATION_URL}

NEXT_WAIT_TIME=1
until [ ${NEXT_WAIT_TIME} -eq 30 ] || [[ ${SYMENV_ACCESS_TOKEN} != "null" && ! -z ${SYMENV_ACCESS_TOKEN} ]]; do
  TOKEN_RESPONSE=$(curl --silent --request POST \
    --url "https://internal-portal.us.auth0.com/oauth/token" \
    --header 'content-type: application/x-www-form-urlencoded' \
    --data grant_type=urn:ietf:params:oauth:grant-type:device_code \
    --data device_code="${DEVICE_CODE}" \
    --data "client_id=STAayma6q8MaHQ1sTOBMNgOzqiq6nomD")
  SYMENV_ACCESS_TOKEN=`echo ${TOKEN_RESPONSE} | jq .access_token | tr -d \"`
  SYMENV_REFRESH_TOKEN=`echo ${TOKEN_RESPONSE} | jq .refresh_token | tr -d \"`
  export SYMENV_ACCESS_TOKEN
  export SYMENV_REFRESH_TOKEN
  sleep $((NEXT_WAIT_TIME++))
done
[ ${NEXT_WAIT_TIME} -lt 30 ]

echo "Got refresh token ${SYMENV_REFRESH_TOKEN}"
echo "Got access token ${SYMENV_ACCESS_TOKEN}"

echo "Getting new access token from refresh token"

curl --request POST \
  --url 'https://internal-portal.us.auth0.com/oauth/token' \
  --header 'content-type: application/x-www-form-urlencoded' \
  --data grant_type=refresh_token \
  --data 'client_id=STAayma6q8MaHQ1sTOBMNgOzqiq6nomD' \
  --data refresh_token="${SYMENV_REFRESH_TOKEN}"
