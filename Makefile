RELEASE   := homepage
NAMESPACE := homepage
TIMEOUT   := 15m

.PHONY: install upgrade uninstall lint deps

## Première installation (ou reinstall complète) — applique les CRDs puis déploie
install: deps
	helm template $(RELEASE) . --namespace $(NAMESPACE) --include-crds \
	  | kubectl apply --server-side -f - --field-manager=helm
	helm upgrade --install $(RELEASE) . \
	  --namespace $(NAMESPACE) --create-namespace \
	  --wait --timeout $(TIMEOUT)

## Mise à jour sans réappliquer les CRDs
upgrade:
	helm upgrade $(RELEASE) . \
	  --namespace $(NAMESPACE) \
	  --wait --timeout $(TIMEOUT)

## Supprime le release Helm (les PVCs et CRDs sont conservés)
uninstall:
	helm uninstall $(RELEASE) -n $(NAMESPACE)

## Vérifie la syntaxe des templates
lint:
	helm lint . --namespace $(NAMESPACE)

## Met à jour les dépendances (sous-charts)
deps:
	helm dependency update
