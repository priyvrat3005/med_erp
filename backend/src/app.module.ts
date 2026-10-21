import { Module } from '@nestjs/common';
import { DbModule } from './common/db.module';
import { HealthController } from './health/health.controller';
import { SyncModule } from './sync/sync.module';

@Module({
  imports: [DbModule, SyncModule],
  controllers: [HealthController],
})
export class AppModule {}
