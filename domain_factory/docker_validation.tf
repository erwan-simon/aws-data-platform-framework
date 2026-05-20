data "external" "docker_check" {
  program = ["sh", "-c", "docker info >/dev/null 2>&1 && echo '{\"running\":\"true\"}' || echo '{\"running\":\"false\"}'"]
}

resource "terraform_data" "docker_validation" {
  lifecycle {
    precondition {
      condition     = data.external.docker_check.result.running == "true"
      error_message = "Docker daemon is not reachable (docker info failed). Start Docker Desktop / OrbStack / colima before running terraform apply — it's required to build the sandbox images (and per-task images via pipeline_factory)."
    }
  }
}
