RELEASE   := homepage
NAMESPACE := homepage
TIMEOUT   := 15m

.PHONY: install upgrade uninstall lint deps

## Première installation (ou reinstall complète) — applique les CRDs puis déploie
install: deps
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm template $(RELEASE) . --namespace $(NAMESPACE) --include-crds \
	  | python3 -c "import sys,yaml; docs=[d for d in yaml.safe_load_all(sys.stdin) if d and d.get('kind')=='CustomResourceDefinition']; print('\n---\n'.join(yaml.dump(d) for d in docs))" \
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
