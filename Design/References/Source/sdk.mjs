import path from 'node:path';
export const sdkRoot=process.env.GUS_OPENPENCIL_SDK_ROOT||path.resolve(path.dirname(process.execPath),'../lib/node_modules/@open-pencil/mcp/node_modules/@open-pencil');
