
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
