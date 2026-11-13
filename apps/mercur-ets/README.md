```bash
  kubectl exec -it -n mercur-ets deployment/mercur-api-server -- \
  bun x medusa user -e admin@etsmtl.club -p "hunter2"

  kubectl exec -it deployment/mercur-api-server -n mercur-ets -- \
  bun x medusa user --invite -e "admin@etsmtl.club"
```
