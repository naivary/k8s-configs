## Pre-requirements

### Erreichbarkeit der Datenbank

Sollte eine externe Datenbank genutzt werden, dann ist es notwendig die
Erreichbarkeit der Datenbank innerhalb des Clusters sicherzustellen. Dafür ist
es erforderlich die folgenden Punkte zu berücksichtigen:

1. Ist die Datenbank auf dem externem System in einem funktionsfähigem Status
   und kann Anfragen entgegen nehmen?
2. Ist die Datenbank über das Netzwerk innerhalb des Clusters erreichbar?

Bei der Datenbank handelt es sich im Standardfall um eine PostgreSQL Datenbank.
In diesem Fall kann die Funktionsfähigkeit mithilfe des folgenden Kommandos
überprüft werden:

```bash
sudo systemctl status postgresql
```

Um die Remote-Erreichbarkeit der Datanbank abzusichern, sind die beiden
Konfigurationsdateien `postgresql.conf` und `pg_hba.conf` anzupassen.
  
```bash
vi /etc/postgresql/<version>/main/postgresql.conf
...
listen_addresses = '*'
...

vi /etc/postgresql/<version>/main/pg_hba.conf
...
local   all             postgres                                md5
local   all             all                                     md5
host    all             all             0.0.0.0/0               md5
host    all             all             ::1/128                 md5
local   replication     all                                     md5
host    replication     all             0.0.0.0/0               md5
host    replication     all             ::1/128                 md5
...
```

Die Erreichbarkeit der Datenbank kann mithilfe des CLI-Clients `psql` überprüft
werden. Dafür ist es notwendig die Client-Programmbibliotheken von PostgreSQL zu
installieren. Auf einem Ubuntu Betriebssystem ist es mit dem folgenden Kommando
möglich:

```bash
sudo apt-get install -y postgresql-client
```

Im Anschluss kann das folgende Kommando genutzt werden, um die Verbindung zu
überprüfen: 

```bash
sudo psql -U postgres

\l
```

### Migration der Datenbank

Die Migration wird mit dem Nutzer `postgres` ausgeführt. In der Migration
werden die notwendigen Datenbanken erstellt, die von Harbor zur Persistierung 
der Metadaten genutzt werden. Die Tabellen innerhalb der Datenbanken werden 
von Harbor gepflegt. 

```bash
CREATE DATABASE notaryserver;
CREATE DATABASE notarysigner;
CREATE DATABASE registry ENCODING 'UTF8';
CREATE DATABASE clair;

CREATE USER harbor;
ALTER USER harbor WITH ENCRYPTED PASSWORD 'harbor';

ALTER DATABASE notaryserver OWNER TO harbor;
ALTER DATABASE notarysigner OWNER TO harbor;
ALTER DATABASE registry OWNER TO harbor;
ALTER DATABASE clair OWNER TO harbor;

\c registry

GRANT ALL PRIVILEGES ON DATABASE notaryserver TO harbor;
GRANT ALL PRIVILEGES ON DATABASE notarysigner TO harbor;
GRANT ALL PRIVILEGES ON DATABASE registry TO harbor;
GRANT ALL PRIVILEGES ON DATABASE clair to harbor;
GRANT ALL ON SCHEMA public TO harbor;
```

### Authentifizierung gegenüber der Datenbank

Falls eine Passwort-Authentifizierung gewählt wurde, ist es erforderlich, in der
Datei `pg_hba.conf` die Verschlüsselungsmethode `md5` zu wählen.

```conf
# vi /etc/postgresql/17/main/pg_hba.conf
local   all             postgres                                md5
...
local   all             all                                     md5
...
host    all             all             0.0.0.0/0               md5
...
host    all             all             ::1/128                 md5
...
host    replication     all             127.0.0.1/0             md5
host    replication     all             ::1/128                 md5
...
```

### values.yaml

Die `values.yaml` wird verwendet für die Konfiguration von Harbor. 
Ein Beispiel kann [hier](values.yaml) vorgefunden werden. In diesem wird
beispielhaft die Domäne `harbor.mh.com` verwendet. Diese sollte ersetzt werden
durch eine valide Domäne. Ebenfalls sollten die gekennzeichneten Felder
(<beispiel-feld>) auf korrekte Werte gesetzt werden.

### Storage Class und CSI Provider

Harbor nutzt für die Persistierung der Container Images und anderer
Informationen PersistentVolumeClaims (PVCs). Die Erstellung und Definition der
zu nutzenden PVCs obliegt dem Nutzer. Eine häufig verwendete Vorgehensweise ist
die Definition von Storage Classes. Mithlife von Storage Classes ist es möglich,
die Provisionierung von PersistentVolumes (PVs) und PVCs zu automatisieren.
Dabei wird ein Container Storage Interface (CSI) Provisioner installiert, der
für die Provisionierung zuständig ist. Welche Storage Class für die
Provisionierung der Komponenten von Harbor genutzt werden soll, kann in der
Datei `values.yaml` definiert werden.

## strictARP: true für metallb (soweit nötig) 

```bash
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system
```

## Installation von metallb (soweit nötig)

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
```

## Erstellen des IP-Pools (soweit nötig)

```bash
k apply -f metallb/ip-pool.yaml
```

## Konfiguration des L2-Modus (soweit nötig)

```bash
k apply -f metallb/adv.yaml
```

## Installation des exemplarischen NFS CSI Drivers (soweit nötig)

```bash
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.9.0/deploy/install-driver.sh | bash -s v4.9.0 --
```

## Deployment des NFS-Servers (soweit nötig)

```bash
kubectl create -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/example/nfs-provisioner/nfs-server.yaml
```

## Erstellen einer Storage Class (soweit nötig)

```bash
kubectl apply -f nfs/storage-class.yaml
```

## Installation von cert-manager (soweit nötig)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml
```

## Deployment des ClusterIssuers (Self Signed)

```bash
kubectl apply -f cert-manager/self_signed-yaml
```

## Installation des NGINX Ingress Controllers (soweit nötig)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0-beta.0/deploy/static/provider/cloud/deploy.yaml
```

## Installation von helm (soweit nötig)

```bash
wget https://get.helm.sh/helm-v3.16.2-linux-arm64.tar.gz
tar -zxvf helm-v3.16.2-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
```

## Hinzufügen des stabilen Repositorys

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

## Hinzufügen des harbor Repositorys

```bash
helm repo add harbor https://helm.goharbor.io
```

## Installation von harbor 

```bash
helm install <my-release-name> harbor/harbor -f values.yaml --namespace harbor-system --create-namespace
```
