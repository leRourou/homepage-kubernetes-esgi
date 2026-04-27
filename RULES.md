## Objectif

Déployer l'application **homepage** (https://github.com/gethomepage/homepage) dans Kubernetes en utilisant idéalement Helm Charts.
Créer un dashboard homepage adapté en fonction de l'objectif de groupe (différent pour chaque groupe).

---

## Règles de Développement

- **Test à chaque itération** : après chaque modification, vérifier que le déploiement fonctionne correctement avant de passer à l'étape suivante.
- **Self-healing** : une fois le développement terminé, tester le comportement de self-healing (suppression de pods, crash, etc.) et s'assurer qu'il respecte les consignes.
- **Scaling** : tester le comportement du scaling (HPA) et s'assurer qu'il respecte les consignes.
- **Documentation finale** : rédiger un document complet contenant toutes les informations sur ce qui a été mis en place (architecture, choix techniques, commandes de test, résultats).

---

## Critères d'Évaluation

### Critère 1 : Exploiter et surveiller l'activité du système (Coeff. 1)
- Maintenir un flux de données en temps réel
- Mettre en place des outils de monitoring
- Administrer les données selon les normes

### Critère 2 : Optimiser l'exploitation des données (Coeff. 2)
- Adapter la visualisation des données
- Optimiser les ressources (écoconception)
- Superviser la répartition de charge

---

## Livrables

### 1. Infrastructure
- **Helm Charts** complets pour tous l'installation de homepage.dev
- **Auto-scaling** configuré (HPA) 
- **Monitoring** avec une stack d'observability opensource (à choisir pour chaque groupe)
- **sauvegarde** avec velero
OPTIONNEL: - Application **fonctionnelle** en haute disponibilité

### 2. Documentation 
- Architecture Kubernetes avec diagrammes
- Guide d'installation
- Analyse comparative avant/après

---

## Contraintes Techniques

- Kubernetes 1.25+
- Helm 3.x
- Haute disponibilité OPTIONNELLE
- autoscaling activé et configuré
- sauvegarde configurée
- Resource limits définis