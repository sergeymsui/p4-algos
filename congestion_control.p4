#include <core.p4>
#include <v1model.p4>

// Ethernet заголовок
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

// IPv4 заголовок
header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<6>  dscp;
    bit<2>  ecn;          // поле ECN для управления перегрузками
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

// Общая структура заголовков
struct headers {
    ethernet_t ethernet;
    ipv4_t     ipv4;
}

// Метаданные (можно расширять)
struct metadata { }

// Парсер
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

// Управление перегрузкой на входе
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    // Регистры для подсчета пакетов и оценки нагрузки
    register<bit<32>>(1) packet_counter;

    action mark_congestion() {
        hdr.ipv4.ecn = 0b11; // Устанавливаем Congestion Experienced (CE)
    }

    table congestion_table {
        actions = {
            mark_congestion;
            NoAction;
        }
        size = 1;
        default_action = NoAction();
    }

    apply {
        if (hdr.ipv4.isValid()) {
            bit<32> pkt_count;
            packet_counter.read(pkt_count, 0);
            packet_counter.write(0, pkt_counter + 1);

            // Простой механизм: при достижении порога маркируем пакеты
            if (pkt_counter > 1000) {
                congestion_table.apply();
            }

            // Простая логика пересылки
            standard_metadata.egress_spec = standard_metadata.ingress_port == 1 ? 2 : 1;
        }
    }
}

// Управление исходящего трафика
control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

// Deparser для восстановления пакета
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        if (hdr.ipv4.isValid()) {
            packet.emit(hdr.ipv4);
        }
    }
}

// Основной контроль коммутатора
V1Switch(MyParser(),
         MyIngress(),
         MyEgress(),
         MyDeparser()) main;
