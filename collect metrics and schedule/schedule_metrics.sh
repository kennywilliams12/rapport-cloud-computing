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