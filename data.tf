# Look up the project number from the project ID
data "google_project" "project" {
  project_id = var.project_id
}