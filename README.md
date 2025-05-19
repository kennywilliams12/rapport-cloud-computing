# rapport-cloud-computing
Rapport de projet Cloud Computing avec Kollaps


## 1. Correction du script de lancement

Au départ, le conteneur ne lançait que le fichier `app.py` au lieu de `Dashboard.py`.
J’ai donc modifié le `Dockerfile` correspondant :

```dockerfile
# Use official Python runtime as the base image
FROM python:3.9

# Set the working directory inside the container
WORKDIR /app

# Copy application code into the container
COPY . /app

# Install necessary Python dependencies
RUN pip install flask

# Expose le port utilisé par Flask
EXPOSE 8088

# Command to run the application inside the container
CMD ["python", "Dashboard.py"]
```

---

## 2. Script de nettoyage complet

Pour repartir d’une base Docker propre, exécute depuis ta **machine hôte** (pas dans un conteneur) :

```bash
echo "➡️ Suppression des stacks Swarm"
docker stack rm iperf3network || true

echo "➡️ Suppression des services restants"
docker service rm $(docker service ls -q) 2>/dev/null || true

echo "➡️ Suppression des conteneurs"
docker container rm -f $(docker ps -aq) 2>/dev/null || true

echo "➡️ Suppression des images"
docker image rm -f $(docker images -q) 2>/dev/null || true

echo "➡️ Suppression des volumes"
docker volume rm $(docker volume ls -q) 2>/dev/null || true

echo "➡️ Suppression des réseaux custom"
docker network rm $(docker network ls --filter "driver=overlay" -q) 2>/dev/null || true
docker network rm kollaps_network 2>/dev/null || true

echo "✅ Docker est propre."
```

### Vérification de l’état global

```bash
echo "📦 Stacks Docker Swarm :"
docker stack ls

echo -e "\n🐳 Conteneurs en cours :"
docker ps -a

echo -e "\n🧊 Images Docker :"
docker images

echo -e "\n🧠 Réseaux Docker :"
docker network ls

echo -e "\n💾 Volumes Docker :"
docker volume ls

echo -e "\n🛠️ Services Swarm :"
docker service ls
```

---

## 3. Reconstruction des images

Toujours depuis la **machine hôte**, dans le dossier `~/Kollaps` :

```bash
cd ~/Kollaps
export DOCKER_BUILDKIT=1

# 1. Build de l’image principale
docker build -f dockerfiles/Kollaps -t kollaps:2.0 .

# 2. Build de l’outil de génération de déploiement
docker build -f dockerfiles/DeploymentGenerator -t kollaps-deployment-generator:2.0 .

# 3. Build de la Dashboard
docker build -f dockerfiles/Dashboard -t kollaps/dashboard:1.0 .
```

---

## 4. Génération de la topologie Kollaps

1. Place-toi dans le dossier des exemples :

   ```bash
   cd ~/Kollaps/examples
   ```
2. Rends l’outil exécutable :

   ```bash
   chmod +x KollapsAppBuilder
   ```
3. Génère le scénario `iperf3network` :

   ```bash
   ./KollapsAppBuilder iperf3network
   ```

   → Un dossier `iperf3network/` apparaît, contenant notamment `topology.xml`.
4. Produit le fichier `topology.yaml` :

   ```bash
   ./KollapsDeploymentGenerator iperf3network/topology.xml -s topology.yaml
   ```
5. Crée le réseau overlay :

   ```bash
   docker network create --driver overlay --subnet 11.1.0.0/20 --attachable kollaps_network
   ```

---

## 5. Déploiement de la stack

```bash
docker stack deploy -c topology.yaml iperf3network
```

> **En cas d’erreur réseau/Swarm**, exécute :
>
> ```bash
> docker network rm ingress || true
> docker swarm leave --force
> docker swarm init
> docker network create --driver overlay --subnet 11.1.0.0/20 --attachable kollaps_network
> cd ~/Kollaps/examples
> docker stack deploy -c topology.yaml iperf3network
> ```

Le nom `iperf3network` est simplement le nom logique de la stack.

---

## 6. Publication du port 8088

Pour être certain que le Dashboard soit accessible depuis l’hôte, ajoute dans **tous** tes fichiers YAML de service :

```yaml
ports:
  - target: 8088
    published: 8088
    protocol: tcp
    mode: host
```

Puis redéploie la stack.

---

## 7. Test avec un navigateur minimal

J’ai installé **links** et testé :

```bash
links http://localhost:8088
```

