# garage-buckets

One OpenTofu root, `terraform/garage-buckets`, that declares Garage S3 buckets
and lands their credentials in OpenBao where exactly one Kubernetes namespace
can read them.
