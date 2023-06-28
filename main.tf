locals {


  external_vpn_gateway_interfaces = {
    "0" = {
      tunnel_address        = aws_vpn_connection.vpn1.tunnel1_address
      vgw_inside_address    = aws_vpn_connection.vpn1.tunnel1_vgw_inside_address
      asn                   = aws_vpn_connection.vpn1.tunnel1_bgp_asn
      cgw_inside_address    = "${aws_vpn_connection.vpn1.tunnel1_cgw_inside_address}/30"
      shared_secret         = aws_vpn_connection.vpn1.tunnel1_preshared_key
      vpn_gateway_interface = 0
      int_num               = 1
    },
    "1" = {
      tunnel_address        = aws_vpn_connection.vpn1.tunnel2_address
      vgw_inside_address    = aws_vpn_connection.vpn1.tunnel2_vgw_inside_address
      asn                   = aws_vpn_connection.vpn1.tunnel2_bgp_asn
      cgw_inside_address    = "${aws_vpn_connection.vpn1.tunnel2_cgw_inside_address}/30"
      shared_secret         = aws_vpn_connection.vpn1.tunnel2_preshared_key
      vpn_gateway_interface = 0
      int_num               = 2
    },
    "2" = {
      tunnel_address        = aws_vpn_connection.vpn2.tunnel1_address
      vgw_inside_address    = aws_vpn_connection.vpn2.tunnel1_vgw_inside_address
      asn                   = aws_vpn_connection.vpn2.tunnel1_bgp_asn
      cgw_inside_address    = "${aws_vpn_connection.vpn2.tunnel1_cgw_inside_address}/30"
      shared_secret         = aws_vpn_connection.vpn2.tunnel1_preshared_key
      vpn_gateway_interface = 1
      int_num               = 3
    },
    "3" = {
      tunnel_address        = aws_vpn_connection.vpn2.tunnel2_address
      vgw_inside_address    = aws_vpn_connection.vpn2.tunnel2_vgw_inside_address
      asn                   = aws_vpn_connection.vpn2.tunnel2_bgp_asn
      cgw_inside_address    = "${aws_vpn_connection.vpn2.tunnel2_cgw_inside_address}/30"
      shared_secret         = aws_vpn_connection.vpn2.tunnel2_preshared_key
      vpn_gateway_interface = 1
      int_num               = 4
    }
  }
}



resource "google_compute_ha_vpn_gateway" "ha_gateway" {
  name    = var.ha_vpn_gateway_name
  project = var.project_id
  region  = var.region
  network = var.network
}

resource "google_compute_router" "router" {
  name                          = var.router_name
  project                       = var.project_id
  region                        = var.region
  network                       = var.network
  bgp {
    asn = var.gcp_router_asn
  }
}

resource "aws_customer_gateway" "customer_gateway1" {
  bgp_asn    = var.gcp_router_asn
  ip_address = google_compute_ha_vpn_gateway.ha_gateway.vpn_interfaces[0].ip_address
  type       = "ipsec.1"
}

resource "aws_customer_gateway" "customer_gateway2" {
  bgp_asn    = var.gcp_router_asn
  ip_address = google_compute_ha_vpn_gateway.ha_gateway.vpn_interfaces[1].ip_address
  type       = "ipsec.1"
}

resource "aws_vpn_gateway" "vpn_gw" {
  vpc_id          = var.aws_vpc
  amazon_side_asn = var.aws_side_asn
}

resource "aws_vpn_connection" "vpn1" {
  vpn_gateway_id        = aws_vpn_gateway.vpn_gw.id
  customer_gateway_id   = aws_customer_gateway.customer_gateway1.id
  type                  = aws_customer_gateway.customer_gateway1.type
  tunnel1_inside_cidr   = var.vpn1-tunnel1-bgp-cidr-range
  tunnel1_preshared_key = var.preshared_key
  tunnel2_inside_cidr   = var.vpn1-tunnel2-bgp-cidr-range
  tunnel2_preshared_key = var.preshared_key
}

resource "aws_vpn_connection" "vpn2" {
  vpn_gateway_id        = aws_vpn_gateway.vpn_gw.id
  customer_gateway_id   = aws_customer_gateway.customer_gateway2.id
  type                  = aws_customer_gateway.customer_gateway2.type
  tunnel1_inside_cidr   = var.vpn2-tunnel1-bgp-cidr-range
  tunnel1_preshared_key = var.preshared_key
  tunnel2_inside_cidr   = var.vpn2-tunnel2-bgp-cidr-range
  tunnel2_preshared_key = var.preshared_key
}

resource "google_compute_external_vpn_gateway" "external_gateway" {
  name            = var.external_peer_gateway_name
  redundancy_type = "FOUR_IPS_REDUNDANCY"

  dynamic "interface" {
    for_each = local.external_vpn_gateway_interfaces
    content {
      id         = interface.key
      ip_address = interface.value["tunnel_address"]
    }
  }
}

resource "google_compute_vpn_tunnel" "tunnels" {
  for_each = local.external_vpn_gateway_interfaces

  name                            = format("tunnel-%d", each.value.int_num)
  router                          = google_compute_router.router.self_link
  ike_version                     = 2
  region                          = var.region
  project                         = var.project_id
  shared_secret                   = each.value.shared_secret
  vpn_gateway                     = google_compute_ha_vpn_gateway.ha_gateway.self_link
  vpn_gateway_interface           = each.value.vpn_gateway_interface
  peer_external_gateway           = google_compute_external_vpn_gateway.external_gateway.self_link
  peer_external_gateway_interface = each.key

}

resource "google_compute_router_interface" "interfaces" {
  for_each = local.external_vpn_gateway_interfaces

  name       = format("tunnel-interface%s", each.key)
  router     = google_compute_router.router.name
  ip_range   = each.value.cgw_inside_address
  region     = var.region
  project    = var.project_id
  vpn_tunnel = google_compute_vpn_tunnel.tunnels[each.key].name

}

resource "google_compute_router_peer" "router_peers" {
  for_each = local.external_vpn_gateway_interfaces

  name            = format("tunnel-peer%s", each.key)
  router          = google_compute_router.router.name
  peer_ip_address = each.value.vgw_inside_address
  peer_asn        = each.value.asn
  region          = var.region
  project         = var.project_id
  interface       = google_compute_router_interface.interfaces[each.key].name

}



