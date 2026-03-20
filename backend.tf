terraform {
  cloud {
    organization = "hashi-demos-apj"

    workspaces {
      name    = "sandbox_consumer_serverlesterraform-agentic-workflows-demo07"
      project = "sandbox"
    }
  }
}
