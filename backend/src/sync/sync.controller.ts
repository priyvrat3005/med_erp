import { Body, Controller, Get, ParseIntPipe, Post, Query, UseGuards, DefaultValuePipe } from '@nestjs/common';
import { Auth } from '../common/auth.decorator';
import { AuthContext, AuthGuard } from '../common/auth.guard';
import { PushDto } from './sync.dto';
import { SyncService } from './sync.service';

@Controller('v1/sync')
@UseGuards(AuthGuard)
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Post('push')
  push(@Auth() auth: AuthContext, @Body() dto: PushDto) {
    return this.sync.push(auth, dto);
  }

  @Get('pull')
  pull(
    @Auth() auth: AuthContext,
    @Query('cursor', new DefaultValuePipe(0), ParseIntPipe) cursor: number,
    @Query('limit', new DefaultValuePipe(500), ParseIntPipe) limit: number,
  ) {
    return this.sync.pull(auth, cursor, limit);
  }
}
