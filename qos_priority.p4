#include <core.p4>
#include <v1model.p4>

// Определение типов заголовков Ethernet и IPv4
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

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

// Структура всех заголовков
struct headers {
    ethernet_t ethernet;
    ipv4_t     ipv4;
}

// Пользовательские метаданные для приоритетов
struct metadata {
    bit<3> priority; // 0 - низкий, 7 - наивысший
}

// Парсер заголовков Ethernet и IPv4
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

// Контроль входящего трафика (Классификация и назначение приоритетов)
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    // Действия для назначения приоритетов
    action set_high_priority() {
        meta.priority = 7;
    }

    action set_medium_priority() {
        meta.priority = 4;
    }

    action set_low_priority() {
        meta.priority = 1;
    }

    table qos_classifier {
        key = {
            hdr.ipv4.diffserv: exact;
        }
        actions = {
            set_high_priority;
            set_medium_priority;
            set_low_priority;
            NoAction;
        }
        size = 256;
        default_action = set_low_priority();
    }

    apply {
        if (hdr.ipv4.isValid()) {
            qos_classifier.apply();
        } else {
            meta.priority = 0; // Нет IPv4 - минимальный приоритет
        }

        // Установка приоритета в стандартных метаданных (очередь)
        standard_metadata.priority = meta.priority;

        // Пересылка пакета на порт назначения (простая логика)
        standard_metadata.egress_spec = standard_metadata.ingress_port == 1 ? 2 : 1;
    }
}

// Выходящий контроль (здесь пустой)
control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

// Депарсер пакетов
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        if (hdr.ipv4.isValid()) {
            packet.emit(hdr.ipv4);
        }
    }
}

// Главная программа коммутатора
V1Switch(MyParser(),
         MyIngress(),
         MyEgress(),
         MyDeparser()) main;
