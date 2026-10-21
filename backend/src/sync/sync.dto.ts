import { Type } from 'class-transformer';
import {
  ArrayMaxSize, IsArray, IsIn, IsObject, IsString, IsUUID, Matches, MaxLength, ValidateNested,
} from 'class-validator';

export const SYNC_ENTITIES = [
  'product', 'supplier', 'customer', 'batch', 'stock_movement',
  'purchase_invoice', 'sales_invoice', 'prescription',
] as const;
export type SyncEntity = (typeof SYNC_ENTITIES)[number];

export class SyncEventDto {
  @IsUUID() eventId!: string;
  @IsIn(SYNC_ENTITIES as unknown as string[]) entity!: SyncEntity;
  @IsIn(['upsert', 'void']) op!: 'upsert' | 'void';
  @IsObject() payload!: Record<string, unknown>;
  // fixed-width HLC: <13-digit ms>-<4 hex counter>-<device code>
  @IsString() @MaxLength(40) @Matches(/^\d{13}-[0-9a-f]{4}-[A-Za-z0-9]{1,4}$/) hlc!: string;
}

export class PushDto {
  @IsArray() @ArrayMaxSize(500) @ValidateNested({ each: true }) @Type(() => SyncEventDto)
  events!: SyncEventDto[];
}

export interface PushResult {
  accepted: string[];
  duplicates: string[];
  rejected: { eventId: string; reason: string }[];
}
