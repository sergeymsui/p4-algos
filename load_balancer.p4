#include <core.p4>
#include <v1model.p4>


// Заголовок Ethernet
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

// Структура заголовков
struct headers {
    ethernet_t ethernet;
}

// Метаданные (не используем в данном примере)
struct metadata {}

// Парсер Ethernet заголовка
parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {
    state start {
        packet.extract(hdr.ethernet);
        transition accept;
    }
}

// Определение количества портов для балансировки нагрузки
const bit<32> NUM_BACKENDS = 4;

// Простая балансировка нагрузки через хэш-функцию
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    action load_balance() {
        // Использование хэш-функции для выбора порта
        bit<32> hash_val;
        hash(hash_val, HashAlgorithm.crc32, 32w0,
             { hdr.ethernet.srcAddr, hdr.ethernet.dstAddr });

        // Выбор одного из NUM_BACKENDS портов
        standard_metadata.egress_spec = (hash_val % NUM_BACKENDS) + 1;
    }

    table lb_table {
        actions = {
            load_balance;
            NoAction;
        }
        size = 1;
        default_action = load_balance();
    }

    apply {
        lb_table.apply();
    }
}

// Контроль выхода (ничего не делаем)
control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

// Контроль де-парсинга пакетов обратно в сеть
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
    }
}

// Основная программа
V1Switch(MyParser(),
         MyIngress(),
         MyEgress(),
         MyDeparser()) main;
