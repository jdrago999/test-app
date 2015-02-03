#!/usr/bin/env ruby

#require 'bundler/setup'
require 'cloudformation-ruby-dsl/cfntemplate'
require 'cloudformation-ruby-dsl/spotprice'
require 'cloudformation-ruby-dsl/table'

template do

  value :AWSTemplateFormatVersion => '2010-09-09'

  value :Description => 'from-scratch'

  parameter 'KeyPairName',
    :Description => 'Name of KeyPair to use.',
    :Type => 'String',
    :MinLength => '1',
    :MaxLength => '40',
    :Default => 'development'

  parameter 'Region',
    :Description => 'Name of region to use.',
    :Type => 'String',
    :MinLength => '1',
    :MaxLength => '40',
    :Default => 'us-east-1'

  mapping 'AWSRegion2AMI',
    :'us-east-1' => { :id => 'ami-1e084b76' },
    :'us-west-2' => { :id => 'ami-xxxxxxxx' }

  resource 'LogBucket', :Type => 'AWS::S3::Bucket', :DeletionPolicy => 'Delete', :Properties => { :AccessControl => 'Private' }

  resource 'RootRole', :Type => 'AWS::IAM::Role', :Properties => {
    :Path => '/',
    :AssumeRolePolicyDocument => {
      :Version => '2012-10-17',
      :Statement => [
        {
          :Sid => '',
          :Effect => 'Allow',
          :Principal => {
            :Service => [
              'codedeploy.us-west-2.amazonaws.com',
              'codedeploy.us-east-1.amazonaws.com'
            ]
          },
          :Action => 'sts:AssumeRole',
        },
        {
          :Sid => "",
          :Effect => "Allow",
          :Principal => {
            :Service => "ec2.amazonaws.com"
          },
          :Action => "sts:AssumeRole"
        }
      ],
    },
    :Policies => [
      {
        :PolicyName => 'root',
        :PolicyDocument => {
          :Version => '2012-10-17',
          :Statement => [
            {
              :Resource => '*',
              :Action => [
                'ec2:Describe*',
                'autoscaling:CompleteLifecycleAction',
                'autoscaling:DeleteLifecycleHook',
                'autoscaling:DescribeLifecycleHooks',
                'autoscaling:DescribeAutoScalingGroups',
                'autoscaling:PutLifecycleHook',
                'autoscaling:RecordLifecycleActionHeartbeat',
              ],
              :Effect => 'Allow',
            },
            {
              :Effect => 'Allow',
              :Action => [ 'logs:*', 's3:GetObject' ],
              :Resource => [
                'arn:aws:logs:*:*:*',
                join('', 'arn:aws:s3:::', ref('LogBucket'), '/*'),
              ],
            },
            {
              :Action => [ 's3:PutObject' ],
              :Effect => 'Allow',
              :Resource => join('', 'arn:aws:s3:::', ref('LogBucket'), '/*'),
            },
            {
              :Effect => "Allow",
              :Action => [
                "s3:Get*",
                "s3:List*"
              ],
              :Resource => [
                "arn:aws:s3:::aws-codedeploy-us-west-2/*",
                "arn:aws:s3:::aws-codedeploy-us-east-1/*",
                "arn:aws:s3:::keys-staging/*"
              ]
            }
          ],
        },
      },
    ],
  }

  resource 'RootInstanceProfile', :Type => 'AWS::IAM::InstanceProfile', :Properties => {
    :Path => '/',
    :Roles => [ ref('RootRole') ],
  }

  resource 'VPC', :Type => 'AWS::EC2::VPC', :Properties => {
    CidrBlock: '10.0.0.0/16',
    EnableDnsSupport: true,
    EnableDnsHostnames: true,
    InstanceTenancy: 'default'
  }

  resource 'VPCSecurityGroup', :Type => 'AWS::EC2::SecurityGroup', :Properties => {
    VpcId: ref('VPC'),
    GroupDescription: 'Allow ssh from everywhere',
    SecurityGroupIngress: [
      {
        IpProtocol: 'tcp',
        FromPort: 22,
        ToPort: 22,
        CidrIp: '0.0.0.0/0'
      }
    ],
    SecurityGroupEgress: [
      {
        IpProtocol: 'tcp',
        FromPort: 0,
        ToPort: 65535,
        CidrIp: '0.0.0.0/0'
      }
    ]
  }

  resource 'PublicSubnet', :Type => 'AWS::EC2::Subnet', :Properties => {
    CidrBlock: '10.0.0.0/24',
    VpcId: ref('VPC'),
    AvailabilityZone: 'us-east-1c',
    Tags: [{Key: 'Name', Value: 'PublicSubnet'}]
  }

  # Create the internet gateway, so we can access the instances in the VPC from the Internet:
  resource 'InternetGateway', :Type => 'AWS::EC2::InternetGateway', :Properties => {
    Tags: [{Key: 'Name', Value: 'InternetGateway for public traffic'}]
  }
  resource 'VPCGatewayAttachment', :Type => 'AWS::EC2::VPCGatewayAttachment', :Properties => {
    InternetGatewayId: ref('InternetGateway'),
    VpcId: ref('VPC')
  }
  resource 'RouteTable', :Type => 'AWS::EC2::RouteTable', :Properties => {
    VpcId: ref('VPC')
  }
  resource 'SubnetRouteTableAssociation', :Type => 'AWS::EC2::SubnetRouteTableAssociation', :Properties => {
    RouteTableId: ref('RouteTable'),
    SubnetId: ref('PublicSubnet')
  }
  resource 'Route', :Type => 'AWS::EC2::Route', :Properties => {
    RouteTableId: ref('RouteTable'),
    GatewayId: ref('InternetGateway'),
    DestinationCidrBlock: '0.0.0.0/0'
  }

  resource 'ServerUser', :Type => 'AWS::IAM::User', :Properties => {
    Path: "/",
    Policies: [
      {
        PolicyName: "cloudformation",
        PolicyDocument: { Statement:[{
          Effect: "Allow",
          Action: [
            "cloudformation:DescribeStackResource",
            "s3:*"
          ],
          Resource: "*"
        }]}
      }
    ]
  }

  resource 'ServerKey', :Type => 'AWS::IAM::AccessKey', :Properties => {
    UserName: ref('ServerUser')
  }




  resource 'LaunchConfig', :Type => 'AWS::AutoScaling::LaunchConfiguration', :Properties => {
    InstanceType: 't2.medium',
    ImageId: find_in_map('AWSRegion2AMI', ref('AWS::Region'), 'id'),
    SecurityGroups: [ref('VPCSecurityGroup')],
    IamInstanceProfile: ref('RootInstanceProfile'),
    KeyName: ref('KeyPairName'),
    AssociatePublicIpAddress: true,
    UserData: base64(interpolate("#!/bin/bash

touch /tmp/user-data-was-here

# Also install the aws credentials:
mkdir /home/ubuntu/.aws
echo '[default]
region = {{ref('AWS::Region')}}
' > /home/ubuntu/.aws/config
echo '[default]
aws_access_key_id = {{ref('ServerKey')}}
aws_secret_access_key = {{get_att('ServerKey', 'SecretAccessKey')}}
' > /home/ubuntu/.aws/credentials

# Now install the ssh key so we can interact with github:
mkdir /home/ubuntu/.ssh
aws s3 cp s3://keys-staging/development.pem /home/ubuntu/.ssh/id_rsa --region {{ref('AWS::Region')}}
chmod 0400 /home/ubuntu/.ssh/id_rsa
# Extract the public key from the private key:
ssh-keygen -y -f /home/ubuntu/.ssh/id_rsa > /home/ubuntu/.ssh/id_rsa.pub
# We want to clone private repos, so add github's ssh key to our known.hosts
# thereby avoiding the interactive prompt to add the key to known_hosts later.
# We this this for github in this way instead of overriding the parameter in .ssh/config
# because we only want to allow this one key -- not just any old key.
ssh-keyscan github.com >> /home/ubuntu/.ssh/known_hosts
chown ubuntu:ubuntu -R /home/ubuntu/.ssh

# Setup ssh keys for root user (since that user does all the work):
mkdir /root/.ssh
cp /home/ubuntu/.ssh/id_rsa /root/.ssh
cp /home/ubuntu/.ssh/id_rsa.pub /root/.ssh
cp /home/ubuntu/.ssh/known_hosts /root/.ssh
chown root:root /root/.ssh/id_rsa* /root/.ssh/known_hosts

"))
  }
  resource 'ASG', :Type => 'AWS::AutoScaling::AutoScalingGroup', :Properties => {
    Tags: [{Key: 'Name', Value: ref('LaunchConfig'), PropagateAtLaunch: true}],
    LaunchConfigurationName: ref('LaunchConfig'),
    MinSize: 1,
    MaxSize: 1,
    DesiredCapacity: 1,
    AvailabilityZones: ['us-east-1c'],
    VPCZoneIdentifier: [ ref('PublicSubnet') ]
  }


  output 'LogBucket',
   :Description => 'Location of logs',
   :Value => ref('LogBucket')
  output 'PublicSubnet',
   :Description => 'PublicSubnet ID',
   :Value => ref('PublicSubnet')

end.exec!
