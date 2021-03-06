# frozen_string_literal: true

require 'test_helper'

class HostTest < ActiveSupport::TestCase
  should have_many(:rule_results)
  should have_many(:rules).through(:rule_results).source(:rule)
  should have_many(:profile_hosts)
  should have_many(:profile_host_profiles).through(:profile_hosts)
                                          .source(:profile)
  should have_many(:policy_hosts)
  should have_many(:test_results)
  should have_many(:policies).through(:policy_hosts)
  should have_many(:assigned_profiles).through(:policies).source(:profiles)
  should have_many(:test_result_profiles).through(:test_results)
  should validate_presence_of :name
  should validate_presence_of :account

  test 'host provides all profiles, assigned and from test results' do
    host = hosts(:one)
    policies(:one).update!(account: host.account)
    policies(:one).hosts << host

    profiles(:one).update!(account: host.account, policy_object: policies(:one))
    test_results(:two).update!(host: host, profile: profiles(:two))

    assert_equal host.all_profiles.count, 2
    assert_includes host.all_profiles.map(&:id), profiles(:one).id
    assert_includes host.all_profiles.map(&:id), profiles(:two).id
  end

  test 'compliant returns a hash with all compliance statuses' do
    host = hosts(:one)
    test_results(:one).update!(host: host, profile: profiles(:one))
    test_results(:two).update!(host: host, profile: profiles(:two))
    expected_result = {
      profiles(:one).ref_id.to_s => false,
      profiles(:two).ref_id.to_s => false
    }
    assert_equal expected_result, host.compliant
  end

  test 'update_from_inventory_host' do
    hosts(:one).update_from_inventory_host!('display_name' => 'foo',
                                            'os_major_version' => 7,
                                            'os_minor_version' => 5)
    assert_equal hosts(:one).name, 'foo'
    assert_equal hosts(:one).os_major_version, 7
    assert_equal hosts(:one).os_minor_version, 5
  end

  test 'update_from_inventory_host with nil fields' do
    hosts(:one).update!(os_major_version: 7, os_minor_version: 5)

    hosts(:one).update_from_inventory_host!('display_name' => 'foo',
                                            'os_major_version' => nil,
                                            'os_minor_version' => nil)
    assert_equal hosts(:one).name, 'foo'
    assert_equal hosts(:one).os_major_version, 7
    assert_equal hosts(:one).os_minor_version, 5
  end

  context 'test result dependent search methods' do
    setup do
      @host = hosts(:one)
      rules(:one).profiles << profiles(:one)
      rules(:two).profiles << profiles(:one)
      test_results(:one).update(host: hosts(:one), profile: profiles(:one))
      RuleResult.create(host: @host, rule: rules(:one),
                        test_result: test_results(:one), result: 'pass')
      RuleResult.create(host: @host, rule: rules(:two),
                        test_result: test_results(:one), result: 'fail')
    end

    should 'total_rules returns the number of rules' do
      assert_equal 2, @host.last_scan_results.count
    end

    should 'rules_passed returns the number of rules that passed' do
      assert_equal 1, @host.rules_passed
    end

    should 'rules_failed returns the number of rules that failed' do
      assert_equal 1, @host.rules_failed
    end

    should 'compliance_score returns the percentage of rules that passed' do
      assert_equal 50.0, @host.compliance_score
    end

    should 'be able to find based on compliance score' do
      assert_includes(
        Host.search_for('compliance_score >= 40 and compliance_score <= 60'),
        hosts(:one)
      )
      assert_not_includes(
        Host.search_for('compliance_score >= 0 and compliance_score <= 39'),
        hosts(:one)
      )
    end

    should 'be able to find based on compliance true/false' do
      assert_not_includes Host.search_for('compliant = true'), hosts(:one)
      assert_includes Host.search_for('compliant = false'), hosts(:one)
      assert_includes Host.search_for('compliant != true'), hosts(:one)
      assert_not_includes Host.search_for('compliant != false'), hosts(:one)
    end

    should 'be able to filter by "has test results"' do
      hosts(:two).test_results.destroy_all
      assert hosts(:one).test_results.present?
      assert hosts(:two).test_results.empty?
      assert_includes Host.search_for('has_test_results = true'), hosts(:one)
      assert_not_includes(Host.search_for('has_test_results = true'),
                          hosts(:two))
      assert_includes Host.search_for('has_test_results = false'), hosts(:two)
      assert_not_includes(Host.search_for('has_test_results = false'),
                          hosts(:one))
    end

    should 'be able to filter by profile_id from test results' do
      assert_includes Host.search_for("profile_id = #{profiles(:one).id}"),
                      hosts(:one)
    end
  end

  context 'scope search by a policy' do
    setup do
      profiles(:one).update!(policy_object: policies(:one),
                             account: accounts(:one))
      policies(:one).hosts << hosts(:one)
    end

    should 'find host using assigned policy id' do
      search = "policy_id = #{policies(:one).id}"
      assert_includes Host.search_for(search), hosts(:one)
    end

    should 'find host using a profile id assigned to the policy' do
      search = "policy_id = #{profiles(:one).id}"
      assert_includes Host.search_for(search), hosts(:one)
    end

    should 'find host using external profile id from its test result' do
      rules(:one).profiles << profiles(:two)
      rules(:two).profiles << profiles(:two)
      test_results(:one).update(host: hosts(:one), profile: profiles(:two))
      RuleResult.create(host: @host, rule: rules(:one),
                        test_result: test_results(:one), result: 'pass')
      RuleResult.create(host: @host, rule: rules(:two),
                        test_result: test_results(:one), result: 'fail')

      search = "policy_id = #{policies(:two).id}"
      assert_includes Host.search_for(search), hosts(:one)
    end

    should 'NOT find host unassigned to the policy even with test results' do
      policies(:one).hosts = []
      profiles(:two).update!(policy_object: policies(:one),
                             external: true,
                             account: accounts(:one))
      rules(:one).profiles << profiles(:two)
      rules(:two).profiles << profiles(:two)
      test_results(:one).update(host: hosts(:one), profile: profiles(:two))
      RuleResult.create(host: @host, rule: rules(:one),
                        test_result: test_results(:one), result: 'pass')
      RuleResult.create(host: @host, rule: rules(:two),
                        test_result: test_results(:one), result: 'fail')

      search = "policy_id = #{policies(:two).id}"
      assert_not_includes Host.search_for(search), hosts(:one)
    end
  end
end
