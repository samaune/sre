#!/usr/bin/env bash

# load the .env file
set -o allexport
source .env
set +o allexport

token=$(cat $k8s_token)

# jq -c '.[]' ./certs.json | while read -r cert; do
#     namespace=$(jq -r '.namespace' <<< "$cert")
#     dns_names=$(jq -r -c '.dns_names' <<< "$cert")
#     printf '%s | %s\n' $namespace $dns_names
#     load_k8s_certs_secrets "$namespace" "$dns_names"
# done

load_k8s_certs_secrets() {
    local ns="$1"
    local dns="$2" #=$(jq -r '.' ./config.json)

    ## k8s - get certificates
    certs=$(curl -H "Authorization: Bearer $token" -k -s $k8s_url/apis/cert-manager.io/v1/namespaces/$ns/certificates \
    | jq --argjson dns "$dns" -r '[.items[]
    | select(.metadata.namespace == "'$ns'")
    | select(.spec.dnsNames[0] as $n | $dns | index($n))
    | {
        dns_name: .spec.dnsNames[0],
        tls_secret: .spec.secretName,
        expired_dt: .status.notAfter,
        issued_dt: .status.notBefore,
        renewal_dt: .status.renewalTime,
    }]')

    ## k8s - secrets crt/key
    secrets=$(curl -H "Authorization: Bearer $token" -k -s $k8s_url/api/v1/namespaces/$ns/secrets?labelSelector=controller.cert-manager.io/fao=true \
    | jq --argjson dns "$dns" -r '[.items[]
    | select(.metadata.namespace == "'$ns'")
    | select(.metadata.annotations["cert-manager.io/alt-names"] as $n | $dns | index($n))
    | {
        # alt_name: .metadata.annotations["cert-manager.io/alt-names"],
        tls_secret: .metadata.name,
        uid: .metadata.uid,
        tls_crt: .data["tls.crt"],
        tls_key: .data["tls.key"]
    }]')

    jq -n --argjson certs "$certs" --argjson secrets "$secrets" '
    $certs as $a
    | $secrets as $b
    | [ $a[] as $x
        | ($b[] | select(.tls_secret == $x.tls_secret)) as $y
        | $x + ($y // {})
        ]
    ' | jq -c '.[]' | while read -r item; do
        dns_name=$(printf '%s\n' "$item" | jq -r '.dns_name')
        expired_dt=$(printf '%s\n' "$item" | jq -r '.expired_dt')
        renewal_dt=$(printf '%s\n' "$item" | jq -r '(.renewal_dt
            | strptime("%Y-%m-%dT%H:%M:%SZ")
            | strftime("%Y%m%d%H%M"))'
        )
        tls_crt=$(printf '%s' "$item" | jq -r '.tls_crt' | base64 -d)
        tls_key=$(printf '%s' "$item" | jq -r '.tls_key' | base64 -d)
        
        echo "======== CERT: [$dns_name] (Renewal At $renewal_dt) ========"
        echo "$tls_crt" | openssl x509 -noout -text | grep -E 'Issuer:|Not Before:|Not After :|Subject:|DNS:'
        echo "----------------------------------------"
        # echo "======== private: ========"

        # awk '{printf "%s\\n", $0}' <<< "$tls_key"
        # echo "======== certificate: ========"
        # awk '{printf "%s\\n", $0}' <<< "$tls_crt"

        # {
        #     "format": "pem",
        #     "private": "",
        #     "certificate": "",
        #     "hsm": false
        # }
    done
}

write_certs_json() {
    local json_data="$1"
    
}

waf_cert_url=${waf_url}/api/v1/conf/webServices/${siteName}/${serverGroupName}/${webServiceName}

# upload_cert_to_waf() {
#     local json_data="$1"
#     curl -k -X POST "/sslCertificates/${sslKeyName}" -H "Cookie: $COOKIE_ID"    
# }

waf_session() {
    
    if [[ "$1" == "login" ]]; then
        waf_cookie=$(curl -k -s -X POST "${waf_url}/api/v1/auth/session" -H "Authorization: Basic $basic_auth" | jq -r '."session-id"')
    fi
    echo "=========== $waf_cookie ==========="  
    curl -k -vv -X DELETE "${waf_url}/api/v1/auth/session" -H "Cookie: $waf_cookie"
    if [[ "$1" == "logout" ]]; then
        curl -k -X DELETE "${waf_url}/api/v1/auth/session" -H "Cookie: $waf_cookie"
    fi
}

waf_session "login"