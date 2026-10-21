import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import * as jwt from 'jsonwebtoken';

export interface AuthContext {
  tenantId: string;
  userId: string;
  deviceId: string;
  role: 'owner' | 'pharmacist' | 'cashier' | 'accountant';
}

/**
 * DEV-ONLY guard (HS256 shared secret). Replace in task T4.1 with asymmetric keys,
 * refresh rotation, device revocation checks and OTP login.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  canActivate(ctx: ExecutionContext): boolean {
    const req = ctx.switchToHttp().getRequest();
    const header: string | undefined = req.headers['authorization'];
    if (!header?.startsWith('Bearer ')) throw new UnauthorizedException();
    try {
      const claims = jwt.verify(header.slice(7), process.env.JWT_SECRET as string, {
        algorithms: ['HS256'],
      }) as jwt.JwtPayload;
      if (!claims.tid || !claims.sub || !claims.did) throw new Error('missing claims');
      req.auth = {
        tenantId: claims.tid,
        userId: claims.sub,
        deviceId: claims.did,
        role: claims.role,
      } as AuthContext;
      return true;
    } catch {
      throw new UnauthorizedException();
    }
  }
}
