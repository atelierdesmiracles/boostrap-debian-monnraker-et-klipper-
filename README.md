# Miracle Klipper — Debian Bootstrap

Bootstrap Debian pour préparer un environnement Klipper + Moonraker + Mainsail. Fluidd n'est pas installé.

## Objectif

- Construire un rootfs Debian minimal pour une architecture cible.
- Installer les dépendances nécessaires à Klipper, Moonraker, la compilation du firmware et la communication série.
- Installer Klipper et Moonraker dans des environnements Python isolés.
- Déployer Mainsail derrière Nginx.
- Préparer les unités systemd, les répertoires persistants et les contrôles de santé.

## Important

Le script de construction crée une archive rootfs destinée à être testée dans un environnement Debian compatible. Il ne crée pas à lui seul une image disque amorçable. Pour un appareil réel, la configuration du noyau, du bootloader, du stockage, du réseau et des périphériques dépend de la cible.

La version initiale cible Debian 12 (Bookworm) et les architectures prises en charge par Debian debootstrap. La construction doit être exécutée sur Linux avec les outils requis et une connexion Internet. Pour une architecture étrangère à l'hôte, installer/configurer QEMU user-mode et binfmt_misc.

## Arborescence

- `scripts/build-rootfs.sh` : construit le rootfs Debian et y exécute la préparation.
- `scripts/setup-rootfs.sh` : installe Klipper, Moonraker, Mainsail, Nginx, les dépendances et les services.
- `.github/workflows/build.yml` : construit les archives pour les architectures configurées.

## Construction locale

```bash
sudo apt-get update
sudo apt-get install -y debootstrap qemu-user-static binfmt-support rsync xz-utils git
sudo ARCH=arm64 ./scripts/build-rootfs.sh
```

Architectures prévues : `amd64`, `arm64`, `armhf`. Vérifier l'architecture de la carte cible avant de choisir.

## Après déploiement

- Mainsail : port HTTP 80
- Moonraker : port 7125 (à garder sur le réseau de confiance ou derrière un mécanisme d'authentification/proxy approprié)
- Klipper : service local, accès à la carte via le port série configuré

La sécurité réseau doit être configurée avant toute exposition à Internet. Ne pas exposer directement Moonraker sur Internet.

## Références

- Octo4a bootstrap builder (inspiration pour le processus rootfs / scripts / CI) : https://github.com/feelfreelinux/octo4a-bootstrap-builder
- Klipper : https://github.com/Klipper3d/klipper
- Moonraker : https://github.com/Arksine/moonraker
- Mainsail : https://github.com/mainsail-crew/mainsail
