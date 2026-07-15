# charts/

Local Helm charts you author yourself (not pulled from a remote repo) go here,
one subdirectory per chart, e.g. `charts/my-app/{Chart.yaml,values.yaml,templates/}`.

Reference from an Application in `argocd/apps/` via:

```yaml
source:
  repoURL: <this-repo-url>
  path: argocd/charts/my-app
  targetRevision: main
```
