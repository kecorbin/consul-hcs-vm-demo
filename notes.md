
Launch an instance of https://play.instruqt.com/hashicorp/tracks/f5-hashicorp-app-mod-tf-consul

Skip to Deploy Legacy environments

Upgrade Consul CLI on workstation

```
workdir=$(pwd)
cd /tmp
rm /usr/local/bin/consul
rm /usr/bin/consul
wget https://releases.hashicorp.com/consul/1.8.0+ent/consul_1.8.0+ent_linux_amd64.zip -O consul.zip
unzip ./consul.zip
mv ./consul /usr/bin/consul
cd $workdir
```

Fetch updated assets

```
workdir=$(pwd)
cd /tmp
rm -rf field-workshops-consul
git clone https://github.com/hashicorp/field-workshops-consul
cd field-workshops-consul
git checkout f5-add-vm-auth
cp -R instruqt-tracks/f5-hashicorp-app-mod-tf-consul/assets/terraform/legacy/* /root/terraform/legacy
cd $workdir

```

Create IAM roles

```
cd /root/terraform/legacy/iam
terraform init
terraform plan
terraform apply -auto-approve

```
Login to Vault and get a consul token

```
vault login -method=userpass username=operations password=Password1
export CONSUL_HTTP_TOKEN=$(vault read -field token consul/creds/ops)
consul acl token read -self
```

Define the policy for the app service

```
mkdir -p /root/policies
cat << EOF > /root/policies/app.hcl
node_prefix "app-" {
  policy = "write"
}
agent "app" {
  policy = "write"
}
key_prefix "_rexec" {
  policy = "write"
}
node_prefix "" {
	policy = "read"
}

service "app" {
  policy = "write"
}
service "app-sidecar-proxy" {
  policy = "write"
}
service_prefix "" {
  policy = "read"
}
EOF
```

Define the policy for the web service

```

cat << EOF > /root/policies/web.hcl
node_prefix "web-" {
  policy = "write"
}
agent "web" {
  policy = "write"
}
key_prefix "_rexec" {
  policy = "write"
}
node_prefix "" {
	policy = "read"
}

service "web" {
  policy = "write"
}
service "web-sidecar-proxy" {
  policy = "write"
}
service_prefix "" {
  policy = "read"
}

EOF
```

Create ACL poliy and role for the app service. 
```
consul acl policy create \
  -name "app-policy" \
  -description "Policy for app service to grant agent permissions" \
  -rules @/root/policies/app.hcl
consul acl role create \
  -name "app-role" \
  -description "Role for the app service" \
  -policy-name "app-policy"

```

Create ACL poliy and role for the web service. 
```
consul acl policy create \
  -name "web-policy" \
  -description "Policy for web service to grant agent permissions" \
  -rules @/root/policies/web.hcl
consul acl role create \
  -name "web-role" \
  -description "Role for the web service" \
  -policy-name "web-policy"

```

Configure Consul to accept JWT's from the Azure MSI service.

```
cat <<EOF > ./jwt_auth_config.json
{
  "BoundAudiences": [
    "https://management.azure.com/"
  ],
  "BoundIssuer": "https://sts.windows.net/${ARM_TENANT_ID}/",
  "JWKSURL":"https://login.microsoftonline.com/${ARM_TENANT_ID}/discovery/v2.0/keys",
  "ClaimMappings": {
      "id": "xms_mirid"
  }
}
EOF
consul acl auth-method create -name azure -type jwt -config @jwt_auth_config.json
consul acl binding-rule create -method=azure -bind-type=role -bind-name=app-role -selector='value.xms_mirid matches `.*/app`'
consul acl binding-rule create -method=azure -bind-type=role -bind-name=web-role -selector='value.xms_mirid matches `.*/web`'
```

Enable/Configure Azure Auth Method

```
vault login root
vault auth enable azure
vault write auth/azure/config \
    tenant_id=$ARM_TENANT_ID \
    resource="https://management.azure.com/" \
    client_id=$ARM_CLIENT_ID \
    client_secret=$ARM_CLIENT_SECRET
```

Stash some secrets in vault

```
rg=$(terraform output -state /root/terraform/vnet/terraform.tfstate resource_group_name)
az hcs get-config -g ${rg} --name hcs
bootstrap_token=$(az hcs create-token --resource-group ${rg} --name hcs | jq  -r .masterToken.secretId)
gossip_key=$(cat consul.json | jq -r '.encrypt')
retry_join=$(cat consul.json | jq -r '.retry_join[0]')
ca=$(cat ca.pem)
vault kv put secret/consul/server master_token=${bootstrap_token}
vault kv put secret/consul/shared gossip_key=${gossip_key} retry_join=$retry_join ca="${ca}"
```

Now that we have a user identity we configure Vault to trust this VM so it can retrieve the gossip key required to bootstrap Consul. This process will be fully automated with native Consul auth in the next release.

```
echo 'path "secret/data/consul/shared" {
  capabilities = ["read"]
}' | vault policy write web -

vault write auth/azure/role/web \
    policies="web" \
    bound_service_principal_ids=$(terraform output -state /root/terraform/legacy/iam/terraform.tfstate web_identity_principal_id) \
    ttl=8h
vault read auth/azure/role/web

```

Repeat for the app role 
```
echo 'path "secret/data/consul/shared" {
  capabilities = ["read"]
}' | vault policy write app -

vault write auth/azure/role/app \
    policies="app" \
    bound_service_principal_ids=$(terraform output -state /root/terraform/legacy/iam/terraform.tfstate app_identity_principal_id) \
    ttl=8h
vault read auth/azure/role/app
```


Apply terraform

```
cd /root/terraform/legacy
terraform plan
terraform apply -auto-approve

```



bastion_ip=$(terraform output -state /root/terraform/vnet/terraform.tfstate bastion_ip)
echo "export bastion_ip=${bastion_ip}" >> ~/.bashrc

ssh -q -A -J azure-user@$bastion_ip azure-user@$web_server
    