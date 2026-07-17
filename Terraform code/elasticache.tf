# 1. Create Security Group for Redis (Allow entire VPC network to access port 6379)
resource "aws_security_group" "redis_sg" {
  name        = "boutique-redis-sg"
  description = "Allow EKS nodes in VPC to access Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Redis traffic from VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block] # Grant access for the entire 10.20.0.0/16 CIDR
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. Declare Subnet Group
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "boutique-redis-subnets"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

# 3. Create Redis Cluster (ElastiCache)
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "boutique-redis-cluster"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids   = [aws_security_group.redis_sg.id]
}

# 4. Export Endpoint URL to configure CartService
output "redis_endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}