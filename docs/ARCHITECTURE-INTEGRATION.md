# Miracle Klipper — architecture et plan d’intégration

Date de vérification : 27 octobre 2026.

Ce document définit la façon d’adapter Klipper, Moonraker et Mainsail à Miracle Klipper sans recopier arbitrairement leurs codebases ni casser les mises à jour amont.

## 1. Décision d’architecture

Miracle Klipper est une distribution/intégration autour de composants upstream :

- **Klipper** : firmware hôte et communication avec le microcontrôleur. Source officielle : https://github.com/Klipper3d/klipper
- **Moonraker** : API Web Python entre le client et Klipper. Source : https://github.com/Arksine/moonraker
- **Mainsail** : interface Web de contrôle, fichiers, historique, macros, webcam et visualisation de mesh. Source : https://github.com/mainsail-crew/mainsail
- **Miracle Klipper** : bootstrap Debian, orchestration, profils/configuration guidée, vérifications, expérience d’installation, tests, documentation, versionnement et paquets livrables.

Ne pas modifier les composants upstream pour y enfouir les fonctions propres à Miracle Klipper. Conserver les dépôts/installations séparés et communiquer par les interfaces documentées de Moonraker et les fichiers de configuration Klipper. Les changements propres au produit se placent dans le bootstrap, les outils auxiliaires et, quand cela sera développé, un configurateur Web indépendant.

## 2. État observé du dépôt de bootstrap

Le README et les scripts du dépôt ont été consultés. Le dépôt construit un rootfs Debian 12 Bookworm minimal pour amd64, arm64 ou armhf, configure des venv Python, installe Klipper et Moonraker, sert Mainsail par Nginx, installe des services systemd et produit une archive tar.xz avec somme SHA-256. Le projet est explicitement Mainsail-only.

### Points positifs

- séparation entre construction de rootfs et configuration du rootfs ;
- venv Python isolés pour Klipper et Moonraker ;
- utilisateur système `klipper` et données imprimante sous `/home/klipper/printer_data` ;
- Moonraker lié à `127.0.0.1:7125` et exposé via Nginx ;
- archive et checksum produits ;
- validation shell et workflow de build présents.

### Risques et corrections prioritaires

1. **Versions non reproductibles** : `git clone --depth 1` des branches par défaut pour Klipper et Moonraker et téléchargement de `releases/latest/download/mainsail.zip`. Une nouvelle construction peut donc changer sans modification du dépôt Miracle Klipper.
2. **Publication en double et fragile** : `.github/workflows/build.yml` publie une release sur push, alors que `.github/workflows/publish-release.yml` référence un identifiant de run en dur et une version v0.1.0 codée en dur. Il faut une seule chaîne de publication pilotée par tag et basée sur les artefacts du run courant.
3. **Configuration Moonraker de sécurité trop permissive pour une exposition réseau** : la liste `trusted_clients` inclut tout `127.0.0.0/8`. Le loopback est utile derrière le proxy local, mais ne jamais élargir ce bloc aux LAN entiers sans comprendre le modèle d’autorisation de Moonraker. Ne jamais exposer directement 7125 sur Internet.
4. **Nginx / proxy** : `client_max_body_size 0` désactive la limite d’upload. Remplacer par une limite explicite configurable adaptée aux gros G-code, et tester WebSocket, upload, API et en-têtes de proxy.
5. **Dépendances du rootfs** : conserver les outils de firmware nécessaires, mais auditer le contenu de base pour réduire ce qui est inutile au runtime. Distinguer explicitement paquets runtime et build si les besoins matériels le permettent.
6. **Matériel incomplet par conception** : le `printer.cfg` initial est un squelette et le service Klipper peut échouer tant que MCU/broches ne sont pas configurés. L’installation doit l’annoncer clairement et fournir un diagnostic expliquant comment relever `/dev/serial/by-id/`.
7. **Tests trop statiques** : `tests/validate.sh` vérifie surtout la syntaxe et quelques chaînes. Ajouter des tests de configuration générée, tests de services, tests de proxy (incluant WebSocket) et tests de vérification des sommes.
8. **Cross-build** : contrôler la configuration binfmt/QEMU pour chaque architecture étrangère et les montages chroot ; faire des builds réels pour amd64, arm64 et armhf plutôt que supposer leur réussite.
9. **Sécurité système** : vérifier les permissions du dossier `printer_data`, les capacités systemd, la mise à jour des paquets, les secrets et le filtrage réseau. Toute nouvelle fonctionnalité de contrôle à distance doit être authentifiée et journalisée.
10. **Versions Debian** : Bookworm est actuellement la seule suite admise par le script. Documenter cette contrainte, puis ajouter une autre suite uniquement après matrice de tests complète.

## 3. Cible fonctionnelle Miracle Klipper

### Cœur d’impression
- Installer, démarrer, arrêter et diagnostiquer Klipper et Moonraker.
- Détecter les cartes connectées via `/dev/serial/by-id/`; ne jamais deviner le port.
- Vérifier la configuration avec Klipper/Moonraker et afficher la cause d’une erreur exploitable.
- Gérer les journaux, la configuration, les fichiers G-code et les sauvegardes.
- Faire remonter température, état de l’impression, progression, temps restant lorsque disponible et erreurs.

### Interface Web
- Mainsail reste l’interface initiale stable. Ne pas réimplémenter son tableau de bord dans le bootstrap.
- Configurateur Miracle Klipper séparé, éventuellement servi sous un chemin Nginx dédié, avec aperçu, validation et export de `printer.cfg`.
- Avant toute écriture d’un fichier actif : sauvegarde horodatée, validation, affichage du diff et possibilité de restauration.
- Prévoir profils machine, carte électronique, MCU, axes, extrudeur, capteurs, endstops, sonde, mesh et macros. Les valeurs propres à une imprimante doivent être confirmées et ne jamais être inventées.
- Intégrer ultérieurement un slicer uniquement via un mécanisme défini (import G-code, association de fichiers ou lien/connexion), sans fusionner son code dans Klipper.

### Diagnostic / mise à jour
- Page de diagnostic indiquant état des services, présence MCU, accès Moonraker, espace disque, version installée et logs.
- Versions upstream verrouillées par un fichier de lock (tag ou commit SHA vérifié) pour les trois composants.
- Mise à jour contrôlée : sauvegarde préalable, récupération de version connue, test, déploiement, possibilité de retour arrière.
- Génération d’un manifeste de build (suite Debian, architecture, date, SHA des commits, version Mainsail et hash de l’archive).

## 4. Architecture cible

```text
Navigateur PC/tablette/téléphone
             |
           Nginx :80
             |------------------------------|
             |                              |
     Mainsail (UI existante)       Miracle Configurator (nouvelle UI)
             |                              |
             +------------ Moonraker API ---+
                              |
                       socket Unix Klipper
                              |
                       Klipper host Python
                              |
                       MCU via USB/UART
                              |
                        imprimante 3D
```

Le configurateur doit être un client de Moonraker, pas un remplacement de Moonraker. Le générateur de configuration doit exploiter une base de profils versionnée et un validateur clairement testable.

## 5. Plan de mise en œuvre par phases

### Phase 0 — rendre le build reproductible
- Introduire un fichier de versions/commits verrouillés.
- Vérifier la compatibilité des dépendances Python du commit Klipper/Moonraker choisi.
- Télécharger une version publiée et vérifiée de Mainsail, ou construire une version/tag connu.
- Générer un manifeste d’artefacts et calculer SHA-256.
- Unifier les workflows : validation PR, build manuel/matrice, publication lors d’un tag signé/versionné (pas de run ID en dur).

### Phase 1 — durcir la base Debian
- Revoir proxy Nginx, taille d’upload, en-têtes et chemins API/WebSocket.
- Vérifier les permissions, les options systemd et la stratégie de pare-feu.
- Éviter l’exposition de Moonraker:7125 ; conserver écoute loopback derrière Nginx.
- Ajouter des tests de démarrage et des tests d’accès à l’API.

### Phase 2 — fiabiliser l’installation
- Script de premier démarrage qui détecte l’architecture, l’état du service et le port série.
- Configuration interactive/assistée via outil séparé ; ne pas démarrer une impression avec profil non validé.
- Messages d’erreur en français, logs faciles à récupérer et sauvegarde/restauration.
- Tester builds propres et mises à niveau depuis la version précédente.

### Phase 3 — configurateur Miracle Klipper
- Front-end responsive pour PC/tablette/mobile.
- Bibliothèque de profils versionnée avec provenance de chaque valeur.
- Formulaire avec validations par champ et dépendances des sections Klipper.
- Génération déterministe, diff, sauvegarde et restauration.
- Contrôles basés sur la version de Klipper installée ; ne pas produire des options inconnues.
- Tests unitaires des profils et tests d’intégration contre un environnement Klipper/Moonraker de test.

### Phase 4 — intégration slicer et fonctions avancées
- Import/export G-code et transfert par API Moonraker.
- Gestion de profils d’imprimantes et sélection de destination.
- File d’attente et suivi de job en réutilisant les capacités existantes de Moonraker/Mainsail.
- Caméras, relais et modules externes uniquement quand la dépendance correspondante est configurée et sécurisée.

### Phase 5 — qualité de livraison
- CI multi-architecture : syntaxe Bash, lint, validation de configurations, build rootfs, checksum et tests post-build.
- Release versionnée avec changelog, manifeste, sommes et instructions d’installation.
- Aucun asset binaire ou firmware sans provenance, version et somme documentées.

## 6. Critères d’acceptation

- Deux builds du même commit et des mêmes versions upstream doivent installer des versions identiques, hors champs explicitement variables comme la date de build.
- Aucun port Moonraker non nécessaire n’est exposé publiquement.
- Les fichiers `printer.cfg` sont sauvegardés avant modification et rejetés si leur validation échoue.
- L’archive est accompagnée d’un SHA-256 et d’un manifeste.
- Les workflows n’utilisent aucun run ID ou tag de release codé en dur.
- Les trois architectures annoncées disposent d’une preuve de build CI.
- Un test post-installation vérifie les services et l’API locale, et explique les étapes matérielles manquantes.
- Le README distingue clairement le rootfs d’une image disque amorçable : le rootfs n’inclut pas à lui seul partitionnement, noyau spécifique ni bootloader.

## 7. Références upstream

- Moonraker README et configuration : https://github.com/Arksine/moonraker
- Klipper README et documentation : https://github.com/Klipper3d/klipper
- Mainsail README, fonctionnalités et releases : https://github.com/mainsail-crew/mainsail
- Dépôt Miracle Klipper : https://github.com/atelierdesmiracles/boostrap-debian-monnraker-et-klipper-

## 8. Licence et attribution

Klipper et Moonraker sont publiés sous GPL-3.0 d’après leurs dépôts. Mainsail expose sa licence dans son dépôt. Avant redistribution, conserver les licences upstream, notices de copyright et sources correspondantes, et vérifier les obligations de chaque composant livré. Ne pas présenter Miracle Klipper comme le projet officiel Klipper, Moonraker ou Mainsail.
