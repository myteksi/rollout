require 'spec_helper'

describe "Rollout" do
  before do
    @redis   = Redis.new
    @rollout = Rollout.new(@redis)
  end

  describe '#activate_city' do
    it 'adds the city id to the live features set if live is passed as true' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: true)
      expect(@redis.sismember('city_cashless_live', 1)).to be true
      expect(@redis.sismember('city_cashless_beta', 1)).to be false
    end

    it 'adds the city id to the beta features set if live is passed as false' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: false)
      expect(@redis.sismember('city_cashless_beta', 1)).to be true
      expect(@redis.sismember('city_cashless_live', 1)).to be false
    end

    it 'if nil city id is passed in it does not do anything' do
      @rollout.activate_city(feature: :cashless, city_id: nil, live: false)
      expect(@redis.sismember('city_cashless_beta', 1)).to be false
      expect(@redis.sismember('city_cashless_live', 1)).to be false
    end

    it 'if nil feature is passed in it does not do anything' do
      @rollout.activate_city(feature: nil, city_id: 1, live: false)
      expect(@redis.sismember('city_cashless_beta', 1)).to be false
      expect(@redis.sismember('city_cashless_live', 1)).to be false
    end
  end

  describe '#deactivate_city' do
    before { @redis.sadd('city_cashless_live', 1) }

    it 'removes the city from both the live set and the beta set' do
      @rollout.deactivate_city(feature: :cashless, city_id: 1)
      expect(@redis.sismember('city_cashless_live', 1)).to be false
    end
  end

  describe '#city_features' do
    it 'returns an empty hash if no feature list is provided' do
      expect(@rollout.city_features(city_id: 1)).to eq({})
    end

    it 'returns nil for features that are specified but do not exist' do
      expect(@rollout.city_features(city_id: 1, feature_list: [:cashless])).to eq({ cashless: nil })
    end

    it 'returns beta for beta features' do
      @rollout.activate_city(feature: :cashless, city_id: 1)
      expect(@rollout.city_features(city_id: 1, feature_list: [:cashless])).to eq({ cashless: 'beta' })
    end

    it 'returns live for live features' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: true)
      expect(@rollout.city_features(city_id: 1, feature_list: [:cashless])).to eq({ cashless: 'live' })
    end
  end

  describe '#activate_user' do
    it 'does not add the user to any list if the feature is non-existent' do
      @rollout.activate_user(feature: :cashless, city_id: 1, id: 1)

      expect(@redis.sismember('user_cashless_blacklist', 1)).to be false
      expect(@redis.sismember('user_cashless_whitelist', 1)).to be false
    end

    it 'does not add the user to any list if the feature is live for the city' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: true)
      @rollout.activate_user(feature: :cashless, city_id: 1, id: 1)

      expect(@redis.sismember('user_cashless_blacklist', 1)).to be false
      expect(@redis.sismember('user_cashless_whitelist', 1)).to be false
    end

    it 'adds the user to the whitelist if the feature is in beta for the city' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: false)
      @rollout.activate_user(feature: :cashless, city_id: 1, id: 1)

      expect(@redis.sismember('user_cashless_blacklist', 1)).to be false
      expect(@redis.sismember('user_cashless_whitelist', 1)).to be true
    end

    it 'removes the user from the blacklist if the feature is live for the city' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: true)
      @rollout.deactivate_user(feature: :cashless, city_id: 1, id: 1)
      expect(@redis.sismember('user_cashless_blacklist', 1)).to be true

      @rollout.activate_user(feature: :cashless, city_id: 1, id: 1)
      expect(@redis.sismember('user_cashless_blacklist', 1)).to be false
    end
  end

  describe '#deactivate_user' do
    it 'does not add the user to any list if the feature is non-existent' do
      @rollout.activate_user(feature: :cashless, city_id: 1, id: 1)

      expect(@redis.sismember('user_cashless_blacklist', 1)).to be false
      expect(@redis.sismember('user_cashless_whitelist', 1)).to be false
    end

    it 'adds the user to the blacklist if the feature is live for the city' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: true)
      @rollout.deactivate_user(feature: :cashless, city_id: 1, id: 1)

      expect(@redis.sismember('user_cashless_blacklist', 1)).to be true
      expect(@redis.sismember('user_cashless_whitelist', 1)).to be false
    end

    it 'does not add the user to any list if the feature is in beta for the city' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: false)
      @rollout.deactivate_user(feature: :cashless, city_id: 1, id: 1)

      expect(@redis.sismember('user_cashless_blacklist', 1)).to be false
      expect(@redis.sismember('user_cashless_whitelist', 1)).to be false
    end

    it 'removes the user from the whitelist if the feature is in beta for the city' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: false)
      @rollout.activate_user(feature: :cashless, city_id: 1, id: 1)
      expect(@redis.sismember('user_cashless_whitelist', 1)).to be true

      @rollout.deactivate_user(feature: :cashless, city_id: 1, id: 1)
      expect(@redis.sismember('user_cashless_whitelist', 1)).to be false
    end
  end

  describe '#user_active?' do
    it 'returns false for a feature that does not exist' do
      expect(@rollout.user_active?(feature: :not_exist, city_id: 1, id: 1)).to be false
    end

    it 'returns false when blacklisted for a feature which is live' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: true)
      @redis.sadd('user_cashless_blacklist', 1)

      expect(@rollout.user_active?(feature: :cashless, city_id: 1, id: 1)).to be false
    end

    it 'returns false when not whitelisted for a feature which is in beta' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: false)
      @redis.srem('user_cashless_whitelist', 1)

      expect(@rollout.user_active?(feature: :cashless, city_id: 1, id: 1)).to be false
    end

    it 'returns true when whitelisted for a feature which is beta' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: false)
      @redis.sadd('user_cashless_whitelist', 1)

      expect(@rollout.user_active?(feature: :cashless, city_id: 1, id: 1)).to be true
    end

    it 'returns true when not blacklisted for a feature which is live' do
      @rollout.activate_city(feature: :cashless, city_id: 1, live: true)
      @redis.srem('user_cashless_blacklist', 1)

      expect(@rollout.user_active?(feature: :cashless, city_id: 1, id: 1)).to be true
    end
  end

  describe '#user_features' do
    it 'returns an empty hash if no feature list is provided' do
      expect(@rollout.user_features(id: 1, city_id: 1)).to eq({})
    end

    it 'returns false for features that are specified but do not exist' do
      expect(@rollout.user_features(id: 1, city_id: 1, feature_list: [:not_exist])).to eq({ not_exist: false })
    end

    it 'returns true if the user is activated for the feature' do
      expect(@rollout).to receive(:user_active?).with(feature: :cashless, city_id: 1, id: 1).and_return true
      expect(@rollout.user_features(id: 1, city_id: 1, feature_list: [:cashless])).to eq({ cashless: true })
    end

    it 'returns false if the user is deactivated for the feature' do
      expect(@rollout).to receive(:user_active?).with(feature: :cashless, city_id: 1, id: 1).and_return false
      expect(@rollout.user_features(id: 1, city_id: 1, feature_list: [:cashless])).to eq({ cashless: false })
    end
  end
end
