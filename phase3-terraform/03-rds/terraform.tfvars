aws_region        = "us-east-1"
project           = "devx"
environment       = "dev"
db_instance_class = "db.t3.micro"
db_name           = "appdb"
db_username       = "appuser"

# NEVER commit real passwords — this is for learning only
# In Phase 4 we use AWS Secrets Manager
db_password = "DevxPassword123!"
