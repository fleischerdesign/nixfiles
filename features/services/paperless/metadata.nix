{
  description = "Paperless-ngx - Document management system";
  features = {
    services.postgresql.enable = true;
    services.redis.enable = true;
  };
}