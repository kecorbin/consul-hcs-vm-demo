#!/bin/bash

#Utils
apt-get update -y
apt-get upgrade -y
sudo apt-get install -y unzip jq nginx

service_id=$(hostname)
hostname=$(hostname)

#get the jwt from azure msi
jwt="$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' -H Metadata:true | jq -r '.access_token')"

#log into vault
token=$(curl -s \
    --request POST \
    --data '{"role": "ingress", "jwt": "'$jwt'"}' \
    http://${vault_server}:8200/v1/auth/azure/login | jq -r '.auth.client_token')

#get the consul secret
consul_secret=$(curl -s \
    --header "X-Vault-Token: $token" \
    http://${vault_server}:8200/v1/secret/data/consul/shared | jq '.data.data')

#extract the bootstrap info
gossip_key=$(echo $consul_secret | jq -r .gossip_key)
retry_join=$(echo $consul_secret | jq -r .retry_join)
ca=$(echo $consul_secret | jq -r .ca)

#debug
echo $gossip_key
echo $retry_join
echo "$ca"

# Install Consul
cd /tmp
wget https://releases.hashicorp.com/consul/1.8.0+ent/consul_1.8.0+ent_linux_amd64.zip -O consul.zip
unzip ./consul.zip
mv ./consul /usr/bin/consul

mkdir -p /etc/consul/config

cat <<EOF > /etc/consul/ca.pem
"$ca"
EOF

# Generate the consul startup script
#!/bin/sh -e
cat <<EOF > /etc/consul/consul_start.sh
#!/bin/bash -e

# Get JWT token from the metadata service and write it to a file
curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' -H Metadata:true -s | jq -r .access_token > ./meta.token

# Use the token to log into the Consul server, we need a valid ACL token to join the cluster and setup autoencrypt
CONSUL_HTTP_ADDR=https://$retry_join consul login -method azure -bearer-token-file ./meta.token -token-sink-file /etc/consul/consul.token

# Generate the Consul Config which includes the token so Consul can join the cluster
cat <<EOC > /etc/consul/config/consul.json
{
  "acl":{
   "enabled":true,
    "down_policy":"async-cache",
    "default_policy":"deny",
    "tokens": {
      "default":"\$(cat /etc/consul/consul.token)"
    }
  },
  "ca_file":"/etc/consul/ca.pem",
  "verify_outgoing":true,
  "datacenter":"${consul_datacenter}",
  "encrypt":"$gossip_key",
  "server":false,
  "log_level":"INFO",
  "ui":true,
  "retry_join":[
    "$retry_join"
  ],
  "ports": {
    "grpc": 8502
  },
  "auto_encrypt":{
    "tls":true
  }
}
EOC

# Run Consul
/usr/bin/consul agent -node=$(hostname) -config-dir=/etc/consul/config/ -data-dir=/etc/consul/data
EOF

chmod +x /etc/consul/consul_start.sh

# Setup Consul agent in SystemD
cat <<EOF > /etc/systemd/system/consul.service
[Unit]
Description=Consul Agent
After=network-online.target

[Service]
WorkingDirectory=/etc/consul
ExecStart=/etc/consul/consul_start.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Install Consul-template
CONSUL_TEMPLATE_VERSION="0.25.1"
curl --silent --remote-name https://releases.hashicorp.com/consul-template/$${CONSUL_TEMPLATE_VERSION}/consul-template_$${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip
unzip consul-template_$${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip
mv consul-template /usr/local/bin/
rm unzip consul-template_$${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip

sudo cat << EOF > /etc/systemd/system/consul-template.service
[Unit]
Description="Template rendering, notifier, and supervisor for @hashicorp Consul and Vault data."
Requires=network-online.target
After=network-online.target
[Service]
User=root
Group=root
ExecStart=/usr/local/bin/consul-template -config=/etc/consul-template/consul-template-config.hcl
ExecReload=/usr/local/bin/consul reload
KillMode=process
Restart=always
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

mkdir --parents /etc/consul-template
mkdir --parents /etc/ssl
touch /etc/consul-template/consul-template-config.hcl


cat << SERVICES >  /etc/consul/config/services.hcl
services = [
  {
    id   = "$(hostname)"
    name = "ingress-gateway"
    port = 8080
    checks = [
      {
        id       = "HTTP-TCP"
        interval = "10s"
        tcp      = "localhost:8080"
        timeout  = "1s"
      }
    ]
  }
]
SERVICES


# Generate consul connect certs for ingress-gateway service
cat << EOF > /etc/ssl/ca.crt.tmpl
{{range caRoots}}{{.RootCertPEM}}{{end}}
EOF

cat << EOF > /etc/ssl/cert.pem.tmpl
{{with caLeaf "ingress-gateway"}}{{.CertPEM}}{{end}}
EOF

cat << EOF > /etc/ssl/cert.key.tmpl
{{with caLeaf "ingress-gateway"}}{{.PrivateKeyPEM}}{{end}}
EOF


# create consul template for nginx config
cat << EOF > /etc/nginx/conf.d/load-balancer.conf.ctmpl
upstream web {
{{range connect "web"}}
  server {{.Address}}:{{.Port}};
{{end}}
}

server {
    listen       8080;
    server_name  localhost;


    location / {
      proxy_pass https://web;
      proxy_http_version 1.1;

      # these refer to files written by templates above
      proxy_ssl_certificate /etc/ssl/cert.pem;
      proxy_ssl_certificate_key /etc/ssl/cert.key;
      proxy_ssl_trusted_certificate /etc/ssl/ca.crt;

    }
}
EOF

# create consul-template Config
cat << EOF > /etc/consul-template/consul-template-config.hcl
template {
source      = "/etc/nginx/conf.d/load-balancer.conf.ctmpl"
destination = "/etc/nginx/conf.d/default.conf"
command = "service nginx reload"
}

template {
  source = "/etc/ssl/ca.crt.tmpl"
  destination = "/etc/ssl/ca.crt"
}
template {
  source = "/etc/ssl/cert.pem.tmpl"
  destination = "/etc/ssl/cert.pem"
}
template {
  source = "/etc/ssl/cert.key.tmpl"
  destination = "/etc/ssl/cert.key"
}
EOF
# Restart SystemD
systemctl daemon-reload

systemctl enable consul
systemctl enable consul-template


systemctl restart consul
systemctl restart consul-template

service nginx restart