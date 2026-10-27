# Miracle Klipper — Debian Bootstrap

Construction d'un rootfs Debian pour héberger **Klipper + Moonraker + Mainsail**. **Fluidd n'est pas installé.**

## Composants

- Debian 12 Bookworm minimal, architectures `amd64`, `arm64`, `armhf`
- Klipper et ses dépendances Python dans un environnement virtuel
- Moonraker et ses dépendances Python dans un environnement virtuel
- Mainsail servi sur HTTP par Nginx
- Services systemd pour Klipper et Moonraker
- Outils de compilation firmware et utilitaires USB/série
- Archive rootfs `.tar.xz` accompagnée d'une somme SHA-256

## Construire localement

Sur un hôte Debian/Ubuntu Linux :

```bash
sudo apt-get update
sudo apt-get install -y debootstrap qemu-user-static binfmt-support xz-utils git
sudo env ARCH=arm64 ./scripts/build-rootfs.sh
```

L'archive apparaît dans `dist/`. `ARCH` accepte `amd64`, `arm64` ou `armhf`. Pour une architecture étrangère à l'hôte, l'exécution nécessite QEMU user-mode configuré par binfmt_misc.

Le contrôle local des scripts se lance avec `./tests/validate.sh` (syntaxe Bash, présence des composants attendus et absence de Fluidd).

## Construire avec GitHub Actions

Dans l'onglet **Actions**, lance **Validate and build Miracle Klipper Debian rootfs** avec *Run workflow* et choisis l'architecture. La validation shell/statique est également exécutée sur les push vers `main` et les pull requests; la construction complète est déclenchée manuellement.

## Après déploiement

- Interface Mainsail : port 80
- Moonraker : port 7125 lié par défaut à `127.0.0.1`; utiliser le proxy Nginx local
- Klipper : socket Unix interne et port série défini dans `/home/klipper/printer_data/config/printer.cfg`

Le rootfs **n'est pas une image disque amorçable** : il ne contient pas de partitionnement, de noyau spécifique à une carte ni de bootloader. L'intégration matérielle est une étape distincte.

## Configuration obligatoire de l'imprimante

Avant usage, adapter `printer.cfg` à la carte électronique, au port série et aux broches réelles. Le fichier de départ n'est pas une configuration complète d'imprimante et Klipper peut rester en erreur tant que la configuration matérielle n'est pas finalisée.

## Sécurité

Ne pas exposer Moonraker directement à Internet. Configurer un contrôle d'accès/authentification et limiter l'interface au réseau de confiance. Réviser la configuration réseau selon l'installation finale.

## Architecture et feuille de route

Consulter [docs/ARCHITECTURE-INTEGRATION.md](docs/ARCHITECTURE-INTEGRATION.md) pour l'analyse des composants upstream, les risques identifiés, l'architecture cible et les phases de développement de Miracle Klipper.

## Références

- Bootstrap d'inspiration : https://github.com/feelfreelinux/octo4a-bootstrap-builder
- Klipper : https://github.com/Klipper3d/klipper
- Moonraker : https://github.com/Arksine/moonraker
- Mainsail : https://github.com/mainsail-crew/mainsail

