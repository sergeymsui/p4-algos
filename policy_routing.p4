#include <core.p4>
#include <v1model.p4>

// Ethernet Header
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

// IPv4 Header
header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

// Заголовки
struct headers {
    ethernet_t ethernet;
    ipv4_t     ipv4;
}

// Метаданные
struct metadata { }

// Parser
parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}

// Ingress control - Policy-based Routing
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    action route(bit<9> port) {
        standard_metadata.egress_spec = port;
    }

    table policy_routing {
        key = {
            hdr.ipv4.srcAddr: lpm;
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            route;
            
            NoAction;
        }
        size = 1024;
        default_action = NoAction();
    }

    apply {
        if (hdr.ipv4.isValid()) {
            policy_routing.apply();
        } else {
            // Default forwarding behavior
            standard_metadata.egress_spec = standard_metadata.ingress_port == 1 ? 2 : 1;
        }
    }
}

// Egress (не используется в этом примере)
control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

// Deparser
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        if (hdr.ipv4.isValid())
            packet.emit(hdr.ipv4);
    }
}

// Main control
V1Switch(MyParser(),
         MyIngress(),
         MyEgress(),
         MyDeparser()) main;
