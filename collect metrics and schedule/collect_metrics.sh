#!/bin/bash

stack_name=$1       # nom du stack Swarm (ex: iperf3network)
interval=$2         # intervalle entre les mesures (en secondes)
duration=$3         # durée totale (en secondes)
topology_name=$4    # nom de la topologie (ex: RUBSC)

if [ -z "$stack_name" ] || [ -z "$interval" ] || [ -z "$duration" ] || [ -z "$topology_name" ]; then
  echo "❌ Usage : $0 <stack_name> <interval_seconds> <total_duration_seconds> <topology_name>"
  echo "Exemple : ./schedule_metrics.sh iperf3network 30 300 RUBSC"
  exit 1
fi

timestamp=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
iterations=$((duration / interval))
run_dir="collect_${stack_name}_${topology_name}_${timestamp}"
mkdir -p "$run_dir"

echo "🕒 Dossier de travail : $run_dir"
echo "🔁 Itérations prévues : $iterations (toutes les $interval sec)"

for ((i=0; i<=iterations; i++)); do
  echo "📡 [$(date +"%T")] Collecte $i/$iterations"

  # Lancer la collecte et déplacer le fichier généré
  csv_file=$(bash collect_metrics.sh "$stack_name" | grep -o 'metrics_.*\.csv')
  if [ -f "$csv_file" ]; then
    mv "$csv_file" "$run_dir/"
  fi

  if [ $i -lt $iterations ]; then
    sleep "$interval"
  fi
done

# Fusionner tous les fichiers CSV générés dans ce répertoire
merged_file="metrics_${stack_name}_${topology_name}_merged_${timestamp}.csv"
echo "📂 Fusion des fichiers dans $merged_file..."

first_file=$(ls "$run_dir"/*.csv | head -n1)
grep -v '^#' "$first_file" | head -n1 > "$merged_file"

for file in "$run_dir"/*.csv; do
  grep -v '^#' "$file" | tail -n +2 >> "$merged_file"
done

echo "✅ Fusion terminée : $merged_file"
echo "📁 Fichiers source stockés dans : $run_dir"
ubuntu@CCBD-2025-10:~/Kollaps/examples$ cat collect_metrics.sh
#!/bin/bash

if [ -z "$1" ]; then
  echo "❌ Utilisation : $0 <nom_du_stack>"
  echo "Exemple : bash collect_metric.sh iperf3network"
  exit 1
fi

stack="$1"
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
outfile="metrics_${stack}_${timestamp}.csv"

echo "========== [ DÉBUT DE LA COLLECTE DE MÉTRIQUES POUR : $stack ] =========="

containers=$(docker ps --format '{{.Names}}' | grep "^${stack}_")

clients=$(echo "$containers" | grep -i "client")
servers=$(echo "$containers" | grep -i "server" | grep -vi "dashboard")
dashboard=$(echo "$containers" | grep -i "dashboard")

echo "📦 Composants détectés :"
echo "- Clients   : $(echo "$clients" | wc -l)"
echo "- Serveurs  : $(echo "$servers" | wc -l)"
echo "- Dashboard : $( [ -n "$dashboard" ] && echo Oui || echo Non )"
echo

if [ -z "$clients" ]; then
  echo "❌ Aucun client détecté. Abandon."
  exit 1
fi

# ========= EN-TÊTE ==========
echo "# timestamp : heure ISO du test" > "$outfile"
echo "# client, server : noms simplifiés" >> "$outfile"
echo "# upload_throughput_mbps : débit montant (Mb/s)" >> "$outfile"
echo "# download_throughput_mbps : débit descendant (Mb/s)" >> "$outfile"
echo "# total_throughput_mbps : somme up+down" >> "$outfile"
echo "# data_transferred_mb : volume estimé échangé" >> "$outfile"
echo "# min/avg/max_latency_ms : latence mesurée" >> "$outfile"
echo "# jitter_ms : différence max-min (approximatif)" >> "$outfile"
echo "# packet_loss_percent : pertes ping" >> "$outfile"
echo "# failed_requests_count : erreurs iperf3" >> "$outfile"
echo "# error_rate_percent : pourcentage d'échec" >> "$outfile"
echo "# tcp_retransmissions : TCP resends détectés" >> "$outfile"

echo "timestamp,client,server,upload_throughput_mbps,download_throughput_mbps,total_throughput_mbps,data_transferred_mb,min_latency_ms,avg_latency_ms,max_latency_ms,jitter_ms,packet_loss_percent,failed_requests_count,error_rate_percent,tcp_retransmissions" >> "$outfile"

for client in $clients; do
  for server in $servers; do
    echo "🔍 Test entre $client → $server"

    client_clean=$(echo "$client" | sed -E "s/^${stack}_//" | sed -E 's/-[0-9a-f]{8}-[0-9a-f\-]{27,}.*//')
    server_clean=$(echo "$server" | sed -E "s/^${stack}_//" | sed -E 's/-[0-9a-f]{8}-[0-9a-f\-]{27,}.*//')

    server_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$server")

    docker exec -d "$server" iperf3 -s

    # ========= PING ==========
    ping_out=$(docker exec "$client" ping -c 10 "$server_ip" 2>/dev/null)

    if [ $? -eq 0 ]; then
      latencies=$(echo "$ping_out" | tail -1 | awk -F'=' '{print $2}' | awk '{print $1}')
      min_latency=$(echo "$latencies" | cut -d '/' -f1)
      avg_latency=$(echo "$latencies" | cut -d '/' -f2)
      max_latency=$(echo "$latencies" | cut -d '/' -f3)

      if [[ -n "$min_latency" && -n "$max_latency" ]]; then
        jitter=$(awk "BEGIN {print ($max_latency - $min_latency)}")
      else
        jitter=""
      fi

      loss=$(echo "$ping_out" | grep -oP '\d+(?=% packet loss)')
    else
      min_latency=""
      avg_latency=""
      max_latency=""
      jitter=""
      loss=""
    fi

    # ========= IPERF3 ==========
    iperf_out=$(docker exec "$client" iperf3 -c "$server_ip" -t 5 -J 2>/dev/null)

    if [ $? -eq 0 ]; then
      upload=$(echo "$iperf_out" | jq '.end.sum_sent.bits_per_second // 0' | awk '{print $1/1000000}')
      download=$(echo "$iperf_out" | jq '.end.sum_received.bits_per_second // 0' | awk '{print $1/1000000}')
      total=$(awk "BEGIN {print $upload + $download}")
      data_mb=$(awk "BEGIN {print ($upload + $download) * 5 / 8}")  # 5s durée
      retrans=$(echo "$iperf_out" | jq '.end.sum_sent.retransmits // 0')
      failed="0"
      errrate="0"
    else
      upload=""
      download=""
      total=""
      data_mb=""
      retrans=""
      failed="1"
      errrate="100"
    fi

    echo "$timestamp,$client_clean,$server_clean,$upload,$download,$total,$data_mb,$min_latency,$avg_latency,$max_latency,$jitter,$loss,$failed,$errrate,$retrans" >> "$outfile"


  done
done

echo
echo "✅ Collecte terminée. Fichier : $outfile"
echo "==============================================================="