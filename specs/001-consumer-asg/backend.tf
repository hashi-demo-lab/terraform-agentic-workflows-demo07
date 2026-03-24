terraform {
  cloud {
    organization = "hashi-demos-apj"
    hostname     = "app.terraform.io"

    workspaces {
      name    = "sandbox_consumer_asgterraform-agentic-workflows-demo07"
      project = "sandbox"
    }
  }
}
