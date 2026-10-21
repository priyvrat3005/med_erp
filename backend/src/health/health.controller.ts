import { Controller, Get } from '@nestjs/common';
import { DbService } from '../common/db.service';

@Controller('health')
export class HealthController {
  constructor(private readonly db: DbService) {}

  @Get()
  async health() {
    return { status: 'ok', db: await this.db.ping() };
  }
}
