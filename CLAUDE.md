# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### JavaScript/Frontend
- `npm run build:script` - Build production JavaScript bundle
- `npm run build:optimized` - Build optimized production bundle
- `npm run analyze:script` - Analyze bundle size with webpack-bundle-analyzer

### Rails Backend
- `rails server` - Start development server
- `rails console` - Interactive Rails console
- `rails db:migrate` - Run database migrations
- `rails db:seed` - Seed database with initial data
- `bundle install` - Install Ruby dependencies
- `bundle exec sidekiq` - Start background job processing

### Testing
No specific test commands found in package.json or Gemfile. Check with the team for testing setup.

## Architecture Overview

This is a Ruby on Rails 7.2 application with React frontend components, built as a Shopify app for COD (Cash on Delivery) order confirmation and management.

### Backend Structure
- **Rails 7.2** with PostgreSQL database
- **Shopify App** integration using shopify_app gem v18.1.2
- **Background Jobs** via Sidekiq with Redis
- **Admin Interface** using Administrate gem
- **Authentication** via Shopify OAuth and custom referral system

### Frontend Structure
- **React 18** components in `app/javascript/packs/`
- **Webpacker 5** for asset compilation
- **Shopify Polaris** design system (v12.6.0)
- **Styled Components** for CSS-in-JS

### Key Models & Domains
- **Shop Management**: Shop, Settings, Plans, UninstalledShop
- **Customer Management**: Customer, CustomerLogin, CustomerShopMapping
- **Order Processing**: OrderConfirmation, PreOrderOtp, PartialRuleSet
- **Communications**: SMS/WhatsApp templates, TwilioLogs, NotificationTemplate
- **Referral System**: ReferralPartner, ReferralShop, ReferralEarning
- **Payment Processing**: Wallet, PayoutEarning, partial payments

### Integration Points
- **Shopify GraphQL** queries in `app/graphql_queries/`
- **Twilio** for SMS/voice communications
- **WhatsApp Business API** for messaging
- **Multiple SMS Providers** (configurable integrations)
- **AWS S3** for file storage
- **Sentry** for error monitoring

### Admin Interfaces
- `/admin` - Main admin dashboard (Administrate)
- `/referral_admin` - Referral partner management
- `/whatsapp_admin` - WhatsApp approval workflows
- `/support_dashboard` - Customer support tools

### Frontend Entry Points
- `app/javascript/packs/hello_react.jsx` - Main app entry
- `app/javascript/packs/order_verify_react.jsx` - Order verification
- `app/javascript/packs/order_prepaid_react.jsx` - Prepaid order handling

### Background Jobs
Uses Sidekiq for:
- Order confirmation processing
- SMS/WhatsApp message sending
- Webhook processing
- Scheduled tasks via sidekiq-cron

### Configuration
- Environment-specific configs in `config/environments/`
- Initializers in `config/initializers/` for service integrations
- Webpacker configs in `config/webpack/`
- Routes defined in `config/routes.rb` with extensive API and admin endpoints

## Key Development Notes

- Uses **Shopify App Bridge v4** for embedded app functionality, loaded via the
  `app-bridge.js` CDN script tag (not the older Provider/Redirect-action
  pattern); `@shopify/app-bridge-react` is still a dependency for its hooks
- Supports multiple countries/currencies with money gem
- Implements complex routing for admin, referral, and public interfaces
- Heavy use of React components with Polaris design system
- Background processing for all external API calls (SMS, WhatsApp, Shopify)

## Skills

- **docs-lookup**: check current React/Svelte/Shopify (Admin API, App Bridge,
  Polaris, webhooks, extensions) documentation before implementing or
  answering — these APIs move fast and training-data memory goes stale.
- **built-for-shopify**: check the app against Shopify's Built for Shopify
  requirements (shopify.dev/docs/apps/launch/built-for-shopify/requirements)
  before/after touching admin navigation, embedded-app behavior, onboarding,
  or UI/design patterns.

See `.claude/skills/` for both.