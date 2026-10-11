resource "netbird_dns_zone" "k8s-zone" {
  name                 = "k8s-zone"
  domain               = "k8s.gewis.nl"
  enabled              = true
  enable_search_domain = true
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_zone" "gewis-zone" {
  name                 = "gewis-zone"
  domain               = "gewis.nl"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "gewisapp01-gewiswg" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewisapp01.gewiswg.gewis.nl"
  type    = "CNAME"
  content = "gewisapp01.net.nb.gewis.nl"
  ttl     = 300
}

resource "netbird_dns_record" "gewisfiles01-gewiswg" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewisfiles01.gewiswg.gewis.nl"
  type    = "CNAME"
  content = "gewisfiles01.gewiswg.net.nb.gewis.nl"
  ttl     = 300
}

resource "netbird_dns_record" "gewisbackup-gewiswg" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewisbackup.gewiswg.gewis.nl"
  type    = "CNAME"
  content = "gewisbackup.net.nb.gewis.nl"
  ttl     = 300
}

resource "netbird_dns_record" "gewisdc02" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewisdc02.gewis.nl"
  type    = "A"
  content = "10.64.123.42"
  ttl     = 300
}

resource "netbird_dns_record" "gewisdc02-gewiswg" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewisdc02.gewiswg.gewis.nl"
  type    = "A"
  content = "10.64.123.42"
  ttl     = 300
}

resource "netbird_dns_record" "gewisdc03" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewisdc03.gewis.nl"
  type    = "A"
  content = "10.64.226.22"
  ttl     = 300
}

resource "netbird_dns_record" "gewisdc03-gewiswg" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewisdc03.gewiswg.gewis.nl"
  type    = "A"
  content = "10.64.226.22"
  ttl     = 300
}

resource "netbird_dns_record" "gewisvdesktop" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewisvdesktop.gewis.nl"
  type    = "CNAME"
  content = "gewisvdesktop.net.nb.gewis.nl"
  ttl     = 300
}

resource "netbird_dns_record" "gewisvdesktop-gewiswg" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewisvdesktop.gewiswg.gewis.nl"
  type    = "CNAME"
  content = "gewisvdesktop.net.nb.gewis.nl"
  ttl     = 300
}

resource "netbird_dns_record" "gewismgmt-gewiswg" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewismgmt.gewiswg.gewis.nl"
  type    = "CNAME"
  content = "gewismgmt.net.nb.gewis.nl"
  ttl     = 300
}

resource "netbird_dns_record" "gewismgmt" {
  zone_id = netbird_dns_zone.gewis-zone.id
  name    = "gewismgmt.gewis.nl"
  type    = "CNAME"
  content = "gewismgmt.net.nb.gewis.nl"
  ttl     = 300
}