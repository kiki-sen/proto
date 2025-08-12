import { bootstrapApplication } from '@angular/platform-browser';
import { APP_INITIALIZER } from '@angular/core';
import { provideHttpClient } from '@angular/common/http';
import { App } from './app/app';
import { ConfigService } from './app/config.service';

function initConfig(cfg: ConfigService) {
  return () => cfg.loadConfig(); // returns a Promise<void>
}

bootstrapApplication(App, {
  providers: [
    provideHttpClient(),                       // or importProvidersFrom(HttpClientModule)
    { provide: APP_INITIALIZER, useFactory: initConfig, deps: [ConfigService], multi: true }
  ]
}).catch(err => console.error(err));
