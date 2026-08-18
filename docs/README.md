# Documentation

[Accueil](../README.md) · [Architecture](architecture.md) · [Exploitation](operations.md) · [Services](services.md) · [Médias](media-stack.md) · [Secrets](secrets.md) · [Reprise](disaster-recovery.md)

## Choisir le bon parcours

| Situation | Commencer ici | Résultat attendu |
|---|---|---|
| nouvelle installation | [Démarrage rapide](../README.md#démarrage-rapide) | hôte prêt et stacks déployées |
| opération quotidienne | [Exploitation](operations.md) | état, logs, mise à jour ou redémarrage |
| ajout d’un service | [Services](services.md#ajouter-un-service) | stack versionnée et déclarée |
| problème de téléchargement | [Media stack](media-stack.md) | VPN, montages et chemins contrôlés |
| rotation d’un secret | [Secrets](secrets.md) | valeur locale remplacée sans fuite Git |
| panne ou remplacement du Pi | [Reprise après sinistre](disaster-recovery.md) | données Restic restaurées avant Docker |

## Modèle mental

```text
Git                     Raspberry Pi                    QNAP
stacks/  ── sync ──▶   /srv/docker/  ── backup ──▶    Restic
config/ ── setup ──▶   /etc/ et /srv                  NFS médias
```

La commande `./homelab` est l’entrée normale. Les scripts de `scripts/` sont
documentés dans leur aide et servent d’implémentation ou de dépannage avancé.

## Conventions

- Toutes les commandes partent de `~/homelab`.
- Les commandes marquées `sudo` changent la configuration de l’hôte.
- Une commande sans `--apply` ou confirmation destructive doit rester sans danger.
- Les valeurs locales sont dans `config/homelab.env` et les `.env` sous `/srv/docker`.
- Ne jamais coller la sortie de `docker compose config` : elle peut révéler des secrets.
