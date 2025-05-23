


# 🚀 Projet Cloud Computing avec Kollaps
Déploiement d’une simulation réseau avec **Kollaps** et **Docker Swarm**, incluant Dashboard et outils de génération de topologie.

Voici une description concise des fichiers présents dans le dépôt GitHub [kennywilliams12/rapport-cloud-computing](https://github.com/kennywilliams12/rapport-cloud-computing/tree/main) :

---

### 📄 Fichiers principaux

* **`README.md`**
  Guide détaillé pour l'installation, la construction et le déploiement d'une simulation réseau avec Kollaps et Docker Swarm.

* **`Cloud Computing Project step by step report.docx`**
  Rapport de projet décrivant étape par étape le processus de mise en place de l'environnement de simulation.

---

### 📁 Scripts de collecte de métriques

* **`collect_metrics.sh`**
  Script pour collecter des métriques réseau (débit, latence, pertes) entre les clients et serveurs définis dans la stack Docker Swarm.

* **`schedule_metrics.sh`**
  Script orchestrateur qui exécute `collect_metrics.sh` à intervalles réguliers pendant une durée spécifiée, consolidant les résultats en un fichier CSV unique.

---

### 🗂️ Fichiers de topologie et visualisation

* **`topologie.xml`**
  Fichier XML décrivant la topologie réseau utilisée pour générer le fichier `topology.yaml` nécessaire au déploiement avec Docker Swarm.

* **`yaml2graph.py`**
  Script Python qui génère une représentation graphique de la topologie réseau à partir du fichier `topology.yaml`, en utilisant Graphviz.

* **`topologies image`**
  Dossier contenant les images générées par `yaml2graph.py`, représentant visuellement les différentes topologies réseau.

---



## 🧰 Prérequis – Installation de Docker

➡️ À faire sur la **machine hôte (VM Ubuntu 22.04)** :

```bash
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ✅ Vérification Docker
sudo docker run hello-world
````

## 📥 Clonage du dépôt Kollaps

➡️ Depuis le **dossier de travail de votre choix** :

```bash
git clone --recurse-submodules https://github.com/miguelammatos/Kollaps.git
cd Kollaps
```

## 📝 Avant de builder : corriger un Dockerfile

➡️ Modifier le fichier `dockerfiles/Dashboard` :

🔧 **Objectif** : s'assurer que c’est bien `Dashboard.py` qui est lancé, pas `app.py`.

```dockerfile
# Base officielle Python 3.9
FROM python:3.9-slim

# Répertoire de travail dans le conteneur
WORKDIR /app

# Copie du code source dans le conteneur
COPY . /app

# Installation des dépendances Python
RUN pip install --no-cache-dir flask

# Exposition du port utilisé par Flask (8088)
EXPOSE 8088

# Commande de lancement de l’application
# Remplace "app.py" par "Dashboard.py" (correction importante)
CMD ["python", "Dashboard.py"]
```

##  Construction des images Docker

➡️ Dans le **dossier racine du dépôt `Kollaps/`** :

```bash
export DOCKER_BUILDKIT=1

# Build de l’image principale
docker build -f dockerfiles/Kollaps -t kollaps:2.0 .

# Build de l’outil de génération
docker build -f dockerfiles/DeploymentGenerator -t kollaps-deployment-generator:2.0 .

# Build de la Dashboard (corrigée)
docker build -f dockerfiles/Dashboard -t kollaps/dashboard:1.0 .
```

---

## 📐 Génération de topologie

➡️ Se rendre dans le dossier `Kollaps/examples/` :

```bash
cd examples
chmod +x KollapsAppBuilder

# 🔧 Crée le dossier iperf3network/
./KollapsAppBuilder iperf3network
```

📝 Le fichier `topology.xml` est généré dans `Kollaps/examples/iperf3network/`.

```bash
# Convertit XML en YAML pour Docker Swarm
./KollapsDeploymentGenerator iperf3network/topology.xml -s topology.yaml
```

✅ Fichier de sortie : `topology.yaml` dans `Kollaps/examples/`

## 🌐 Création du réseau Docker overlay

➡️ Depuis n’importe où :

```bash
docker network create --driver overlay --subnet 11.1.0.0/20 --attachable kollaps_network
```

## 📤 Déploiement de la stack

➡️ Dans `Kollaps/examples/` où se trouve `topology.yaml` :

```bash
docker stack deploy -c topology.yaml iperf3network
```

## 🔧 En cas d’erreur de Swarm (réseau, ingress, etc.)

➡️ À exécuter si le déploiement échoue :

```bash
docker network rm ingress || true
docker swarm leave --force
docker swarm init

docker network create --driver overlay --subnet 11.1.0.0/20 --attachable kollaps_network

cd ~/Kollaps/examples
docker stack deploy -c topology.yaml iperf3network
```

---

## 🌍 Accès au Dashboard (port 8088)

📝 Avant de déployer, dans **topology.yaml**, assure-toi que la section du service `dashboard` contient bien :

```yaml
ports:
  - target: 8088
    published: 8088
    protocol: tcp
    mode: host
```

➡️ Puis redéploie la stack :

```bash
docker stack deploy -c topology.yaml iperf3network
```

✅ Le Dashboard est maintenant disponible sur :
📍 `http://localhost:8088`


## ✅ Vérification de l’état du déploiement

```bash
docker stack ls
docker service ls
docker ps -a
docker network ls
```

