node_prefix "web-" {
  policy = "write"
}
agent_prefix "web-" {
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

