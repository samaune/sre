#!/usr/bin/env bash

# load the .env file
set -o allexport
source .env
set +o allexport

init() {
    jq -c '.[]' ./data/config.json | while read -r cert; do
        namespace=$(jq -r '.namespace' <<< "$cert")
        dns_names=$(jq -r -c '.dns_names' <<< "$cert")
        printf '%s | %s\n' $namespace $dns_names

        ## k8s - get certificates
        curl -H "Authorization: Bearer $k8s_token" \
        -ks $k8s_url/apis/cert-manager.io/v1/namespaces/$namespace/certificates \
        | jq --argjson dns "$dns_names" -r '[.items[]
        | select(.metadata.namespace == "'$namespace'")
        | select(.spec.dnsNames[0] as $n | $dns | index($n))]' \
        | jq -c '.[]' \
        | while read -r item; do
            dns_name=$(printf '%s\n' "$item" | jq -r '.spec.dnsNames[0]')
            tls_secret=$(printf '%s\n' "$item" | jq -r '.spec.secretName')
            expired_dt=$(printf '%s\n' "$item" | jq -r '(.status.notAfter
                | strptime("%Y-%m-%dT%H:%M:%SZ")
                | strftime("%Y%m%d%H%M"))'
            )
            
            waf_upload_cert "$dns_name" "$expired_dt" "$namespace" "$tls_secret"
        done
    done
}

waf_upload_cert() {
    
    local serverGroupName=$1 # dns/cn name
    local expired_dt=$2
    local namespace=$3
    local secretName=$4

    gwPort=$WAF_GW_PORT
    gwgrpName=$(jq -rn --arg v "$WAF_GW_GROUP_NAME" '$v|@uri')
    aliasName=$(echo "NW-${serverGroupName//.nagaworld.com/}" | tr '[:lower:]' '[:upper:]')  
    sslKeyName="${aliasName}_${expired_dt}"

    waf_cert_url=${WAF_URL}/conf/webServices/${WAF_SITE_NAME}/${serverGroupName}/${WAF_SERVICE_NAME}
    
    #curl -k -vv -X DELETE "${waf_cert_url}/sslCertificates/NW_MYPORTAL_1760861560000\n"  -H "Cookie: $WAF_COOKIE"
    sslCertificates=$(curl -ks "$waf_cert_url/sslCertificates" -H "Cookie: $WAF_COOKIE" | jq -c '.') 
    matched=$(echo "$sslCertificates" | jq -e --arg k "$sslKeyName" -r '.sslKeyName[] | select(.== $k)')
    
    if [ -z "$matched" ]; then # -n exist | -z not exist
        payload=$(curl -H "Authorization: Bearer $k8s_token" \
        -ks $k8s_url/api/v1/namespaces/$namespace/secrets/$secretName \
        | jq -r '{
            format: "pem",
            private: (.data["tls.key"] | @base64d),
            certificate: (.data["tls.crt"] | @base64d),
            hsm: false
        }')

        curl -k -X POST "${waf_cert_url}/sslCertificates/${sslKeyName}" \
            -d "$payload" \
            -H "Cookie: $WAF_COOKIE" \
            -H "Content-Type: application/json"

        ### (| @json => | @text) 
        echo "======== DNS: [$serverGroupName] (SSL_KEY_NAME $sslKeyName) ========"
        # echo "$payload" | jq -r '.certificate | @text' \
        # | openssl x509 -noout -text \
        # | grep -E 'Issuer:|Not Before:|Not After :|Subject:|DNS:'
        # echo "======================================================"
        
        ################# Update NGRP Inbound ###################
        
        curl -k -X PUT "${waf_cert_url}/krpInboundRules/${gwgrpName}/${aliasName}/${gwPort}" \
            -H "Cookie: $WAF_COOKIE" \
            -H "Content-Type: application/json" \
            -d "{\"serverCertificate\": \"$sslKeyName\"}"
        curl -k "${waf_cert_url}/krpInboundRules/${gwgrpName}/${aliasName}/${gwPort}" -H "Cookie: $WAF_COOKIE" | jq -r '.'
        
    fi

    ##### Remove Unused Certificates #####
    echo "$sslCertificates" \
    | jq -e --arg k "$sslKeyName" -r '.sslKeyName[] | select(.!= $k)' \
    | while read -r DelsslKeyName; do
        curl -k -X DELETE "${waf_cert_url}/sslCertificates/${DelsslKeyName}"  -H "Cookie: $WAF_COOKIE"
    done
}

waf_session() {
    if [[ "$1" == "login" ]]; then
        WAF_COOKIE=$(curl -k -s -X POST "${WAF_URL}/auth/session" \
        -H "Authorization: Basic $basic_auth" | jq -r '."session-id"')
        echo $WAF_COOKIE
    fi
    if [[ "$1" == "logout" ]]; then
        curl -k -X DELETE "${WAF_URL}/auth/session" -H "Cookie: $WAF_COOKIE"
    fi
}
# waf_session $1
init