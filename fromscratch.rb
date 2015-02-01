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
    :'us-east-1' => { :id => 'ami-86562dee' },
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
                "arn:aws:s3:::aws-codedeploy-us-east-1/*"
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
    UserData: base64('#!/bin/bash

touch /tmp/user-data-was-here
apt-get update
apt-get install -y ruby2.0
ruby --version
cd /home/ubuntu
wget -O install "https://gist.github.com/jdrago999/6f93c3b95423fa9bf8c7/raw/aa2a23e106b5658250c025c9b90c720c34210762/codedeploy-latest.rb"
chmod +x ./install
./install auto
sudo service codedeploy-agent start
touch /tmp/codedeploy-agent-installed-ok
')
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
