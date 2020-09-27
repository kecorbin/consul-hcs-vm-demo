node_prefix "ingress-" {
        policy = "write"
    }
    agent_prefix "ingress-" {
        policy = "write"
    }
    key_prefix "_rexec" {
        policy = "write"
    }
    node_prefix "" {
        policy = "read"
    }

    service "ingress-gateway" {
        policy = "write"
    }
    service_prefix "" {
        policy = "read"
    }
