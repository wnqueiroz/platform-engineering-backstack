import { Entity } from '@backstage/catalog-model';
import {
  EntityProvider,
  EntityProviderConnection,
} from '@backstage/plugin-catalog-node';
import {
  LoggerService,
  RootConfigService,
  SchedulerServiceTaskRunner,
} from '@backstage/backend-plugin-api';

export class CrossplaneEntityProvider implements EntityProvider {
  private connection?: EntityProviderConnection;

  constructor(
    private readonly opts: {
      logger: LoggerService;
      config: RootConfigService;
      taskRunner: SchedulerServiceTaskRunner;
    },
  ) {}

  getProviderName(): string {
    return 'crossplane-entity-provider';
  }

  async connect(connection: EntityProviderConnection): Promise<void> {
    this.connection = connection;

    await this.opts.taskRunner.run({
      id: this.getProviderName(),
      fn: async () => {
        try {
          await this.run();
        } catch (error: any) {
          this.opts.logger.error(
            `[${this.getProviderName()}] Failed to run`,
            error,
          );
        }
      },
    });
  }

  private async run(): Promise<void> {
    if (!this.connection) throw new Error('Provider not connected');

    const clusterMethods =
      this.opts.config.getOptionalConfigArray(
        'kubernetes.clusterLocatorMethods',
      ) ?? [];

    for (const method of clusterMethods) {
      if (method.getString('type') !== 'config') continue;

      const clusters = method.getOptionalConfigArray('clusters') ?? [];
      if (clusters.length === 0) {
        this.opts.logger.warn(
          `[${this.getProviderName()}] No clusters found in config`,
        );
        continue;
      }

      for (const cluster of clusters) {
        await this.processCluster(cluster);
      }
    }
  }

  private async processCluster(cluster: any): Promise<void> {
    const clusterName = cluster.getString('name');
    const server = cluster.getString('url');
    const token = cluster.getOptionalString('serviceAccountToken');
    const namespace =
      cluster.getOptionalString('serviceAccountNamespace') ?? 'default';
    const skipTLSVerify = cluster.getOptionalBoolean('skipTLSVerify') ?? false;

    const k8sClient = await import('@kubernetes/client-node');

    const kc = new k8sClient.KubeConfig();

    kc.loadFromOptions({
      clusters: [{ name: clusterName, server, skipTLSVerify }],
      users: [{ name: 'backstage', token }],
      contexts: [
        {
          name: 'backstage-context',
          user: 'backstage',
          cluster: clusterName,
          namespace,
        },
      ],
      currentContext: 'backstage-context',
    });

    const customObjectsApi = kc.makeApiClient(k8sClient.CustomObjectsApi);

    let claims;
    try {
      const res = await customObjectsApi.listNamespacedCustomObject({
        group: 'platform.hooli.tech',
        version: 'v1alpha1',
        plural: 'xqueuesclaim',
        namespace: 'crossplane-system',
      });

      claims = res.items;
    } catch (err: any) {
      this.opts.logger.error(
        `[${this.getProviderName()}] Failed to fetch claims from ${clusterName} cluster`,
        err,
      );
      return;
    }

    if (!claims?.length) {
      this.opts.logger.warn(
        `[${this.getProviderName()}] No claims found in cluster ${clusterName}`,
      );
      return;
    }

    const entities = this.toEntities(claims);
    const locationKey = `bootstrap:${this.getProviderName()}`;

    await this.connection?.applyMutation({
      type: 'full',
      entities: entities.map(entity => ({
        entity,
        locationKey,
      })),
    });

    this.opts.logger.info(
      `[${this.getProviderName()}] Registered ${
        entities.length
      } claims from ${clusterName} cluster`,
    );
  }

  private toEntities(claims: any[]): Entity[] {
    return claims.map((claim: any) => {
      const statusConditions = (claim.status?.conditions ?? []).reduce(
        (acc: Record<string, string>, cond: any) => {
          acc[cond.type] = cond.status;
          return acc;
        },
        {},
      );

      const createdAt = claim.metadata?.creationTimestamp;
      const lastSynced = claim.status?.conditions?.find(
        (c: any) => c.type === 'Synced',
      )?.lastTransitionTime;

      return {
        apiVersion: 'backstage.io/v1alpha1',
        kind: 'Resource',
        metadata: {
          name: claim.metadata.name,
          namespace: 'default',
          description: `Crossplane XQueueClaim provisioned with provider ${claim.spec.providerName}`,
          annotations: {
            'backstage.io/kubernetes-id': claim.metadata.name,
            'backstage.io/managed-by-location': `bootstrap:${this.getProviderName()}`,
            'backstage.io/managed-by-origin-location': `bootstrap:${this.getProviderName()}`,
          },
          tags: Object.entries(claim.spec.tags ?? {}).map(
            ([k, v]) => `${k}:${v}`,
          ),
        },
        spec: {
          type: 'xqueueclaim',
          system: 'infrastructure',
          owner: 'guests',
          lifecycle: 'production',
          provider: claim.spec.providerName,
          location: claim.spec.location,
          maxMessageSize: claim.spec.maxMessageSize,
          visibilityTimeoutSeconds: claim.spec.visibilityTimeoutSeconds,
          queueName: claim.spec.resourceRef?.name,
          status: statusConditions,
          createdAt,
          lastSynced,
        },
      };
    });
  }
}
