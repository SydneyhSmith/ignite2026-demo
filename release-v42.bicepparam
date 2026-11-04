// Deploys a release through Bicep: prod + a pinned image.
using 'main.bicep'

extends 'prod.bicepparam'

param webImage = 'ghcr.io/sydneyhsmith/orders-web:v42'
