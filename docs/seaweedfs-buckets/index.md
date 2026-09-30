# seaweedfs-buckets

One OpenTofu root, `terraform/seaweedfs-buckets`, that declares SeaweedFS S3
buckets and lands their credentials in OpenBao where exactly one Kubernetes
namespace can read them.

Two providers, no third-party ones: `hashicorp/aws` talks to the S3 and IAM APIs
that SeaweedFS serves on a single port, and `hashicorp/vault` writes the
resulting keys into OpenBao. The server side of that endpoint is
[s3-01](../s3-01/seaweedfs.md).

Buckets are owned here and nowhere else; Nix on s3-01 carries no bucket names.
See [The declaration](declaration.md).
