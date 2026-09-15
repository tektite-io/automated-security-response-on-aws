// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import { App } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { MemberCloudTrailStack } from './cloud-trail';

function getTemplate(): Template {
  const app = new App();
  const stack = new MemberCloudTrailStack(app, 'MemberCloudTrailStack', {});
  return Template.fromStack(stack);
}

describe('member CloudTrail stack', () => {
  it('does not give the S3 trigger role an explicit name', () => {
    const template = getTemplate();

    const roles = Object.values(template.findResources('AWS::IAM::Role'));
    const s3AssumableRoles = roles.filter((role) => {
      const statements = role.Properties?.AssumeRolePolicyDocument?.Statement ?? [];
      return statements.some(
        (statement: { Principal?: { Service?: unknown } }) => statement.Principal?.Service === 's3.amazonaws.com',
      );
    });

    expect(s3AssumableRoles).toHaveLength(1);
    // This stack is nested in the per-region member stack, but an IAM role is
    // account-global. A hardcoded name makes a second regional deployment into the
    // same account fail with "role already exists". Nothing looks this role up by
    // name, so CloudFormation must generate it.
    expect(s3AssumableRoles[0].Properties).not.toHaveProperty('RoleName');
  });
});
