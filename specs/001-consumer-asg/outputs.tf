output "alb_dns_name" {
  description = "Internal DNS name of the application load balancer."
  value       = module.alb.dns_name
}

output "alb_security_group_id" {
  description = "Security group attached to the internal ALB front door."
  value       = module.alb.security_group_id
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group name for operations and monitoring."
  value       = module.autoscaling.autoscaling_group_name
}

output "instance_security_group_id" {
  description = "Security group ID attached to application instances."
  value       = module.instance_sg.security_group_id
}

output "launch_template_id" {
  description = "Launch template identifier created for the compute fleet."
  value       = module.autoscaling.launch_template_id
}

output "target_group_arn" {
  description = "Target group ARN used for application traffic registration."
  value       = module.alb.target_groups["app"].arn
}
