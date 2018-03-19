#!/usr/bin/env bash

version=6.1.2

rpm -ivh https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$version.rpm
/usr/share/elasticsearch/bin/elasticsearch-plugin install ingest-geoip
/usr/share/elasticsearch/bin/elasticsearch-plugin install ingest-user-agent
#/usr/share/elasticsearch/bin/elasticsearch-plugin install x-pack
/usr/share/elasticsearch/bin/elasticsearch-plugin install https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v$version/elasticsearch-analysis-ik-$version.zip
/usr/share/elasticsearch/bin/elasticsearch-plugin install https://github.com/medcl/elasticsearch-analysis-pinyin/releases/download/v$version/elasticsearch-analysis-pinyin-$version.zip

#https://github.com/o19s/elasticsearch-learning-to-rank

mkdir -p /etc/sysctl.d
echo "vm.max_map_count=262144" > /etc/sysctl.d/11-es.conf
echo -ne '* soft nproc 8192 \nelasticsearch  -  nofile  65536' > /etc/security/limits.d/es.conf

echo -ne '''
ES_HOME=/usr/share/elasticsearch/

ES_HEAP_SIZE=128m
MAX_OPEN_FILES=65535
MAX_MAP_COUNT=262144
LOG_DIR=/var/log/elasticsearch
WORK_DIR=/tmp/elasticsearch/
CONF_DIR=/etc/elasticsearch/
ES_PATH_CONF=/etc/elasticsearch/
RESTART_ON_UPGRADE=true
PID_DIR=/var/run/elasticsearch
JAVA_HOME=/usr/java/default
ES_STARTUP_SLEEP_TIME=5
ES_JAVA_OPTS="-Des.index.max_number_of_shards=128 -verbose:gc -Xloggc:/var/log/elasticsearch/elasticsearch_gc.log -XX:-CMSConcurrentMTEnabled -XX:+PrintGCDateStamps -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:ErrorFile=/var/log/elasticsearch/elasticsearch_err.log -XX:ParallelGCThreads=8"
MAX_LOCKED_MEMORY=unlimited
MAX_MAP_COUNT=262144
'''> /etc/sysconfig/elasticsearch

memory=`free -g | awk 'NR==2{printf $2}'`g


echo -ne '''
-Xms'''$memory'''
-Xmx'''$memory'''
-XX:+UseConcMarkSweepGC
-XX:CMSInitiatingOccupancyFraction=75
-XX:+UseCMSInitiatingOccupancyOnly
-XX:+AlwaysPreTouch
-server
-Xss1m
-Djava.awt.headless=true
-Dfile.encoding=UTF-8
-Djna.nosys=true
-Djdk.io.permissionsUseCanonicalPath=true
-XX:-OmitStackTraceInFastThrow
-Dio.netty.allocator.type=unpooled
-Dio.netty.noUnsafe=true
-Dio.netty.noKeySetOptimization=true
-Dio.netty.recycler.maxCapacityPerThread=0
-Dlog4j.shutdownHookEnabled=false
-Dlog4j2.disable.jmx=true
-XX:+HeapDumpOnOutOfMemoryError
-XX:+PrintGCDetails
-XX:+PrintGCTimeStamps
-XX:+PrintGCDateStamps
-XX:+PrintClassHistogram
-XX:+PrintTenuringDistribution
-XX:+PrintGCApplicationStoppedTime
-XX:+UseGCLogFileRotation
-XX:NumberOfGCLogFiles=32
-XX:GCLogFileSize=128M
'''> /etc/elasticsearch/jvm.options

SERVER_IP=`/sbin/ifconfig  | grep 'inet'| grep -v '127.0.0.1' |head -n1 |tr -s ' '|cut -d ' ' -f3 | cut -d: -f2`
hostname=`hostname -f`

echo -ne '''
cluster.name: logcenter
node.name: '''$hostname'''
network.host: '''$SERVER_IP'''
discovery.zen.ping.unicast.hosts: ["10.19.0.97","10.19.0.98","10.19.0.99","10.19.0.100"]
discovery.zen.minimum_master_nodes: 2
path:
  data:
    - /data01/es
    - /data02/es
    - /data03/es
    - /data04/es
    - /data05/es
    - /data06/es
    - /data07/es
    - /data08/es
    - /data09/es
    - /data10/es
    - /data11/es
    - /data12/es
  logs: /var/log/elasticsearch

bootstrap.system_call_filter: false
bootstrap.memory_lock: true
http.port: 920

action.destructive_requires_name: true

indices.requests.cache.size: 2%
index.queries.cache.everything: true
indices.breaker.fielddata.limit: 10%
indices.fielddata.cache.size: 20%

#queue_size = number of waiting requests
thread_pool.search.queue_size: 5000
thread_pool.bulk.queue_size: 500

node.attr.rack: rack1
node.attr.size: big
''' > /etc/elasticsearch/elasticsearch.yml

sudo swapoff -a

systemctl enable elasticsearch
systemctl start elasticsearch

curl -XPUT 'http://'$SERVER_IP':9200/_template/index_template' -H 'Content-Type: application/json' -d '{
    "index_patterns" : ["*"],
    "settings" : {
        "number_of_replicas" : 1,
        "number_of_shards" : 64,
        "routing_partition_size" : 4,
        "index.merge.policy": {
          "segments_per_tier": 50,
          "max_merge_at_once": 50,
          "max_merged_segment": "1gb"
        },
        "persistent" : {
            "cluster.routing.allocation.disk.watermark.low" : "70%",
            "cluster.routing.allocation.disk.watermark.high" : "85%",
            "indices.recovery.max_bytes_per_sec": "20mb"
        },
        "index.translog": {
          "index.translog.durability": "async"
        }
    }
}'
