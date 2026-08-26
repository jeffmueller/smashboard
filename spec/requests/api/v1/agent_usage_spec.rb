# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AgentUsage' do
  let(:user) { create(:user) }
  let(:headers) { api_headers_for(user) }
  let(:collector_payload) do
    { 'ready' => true, 'tierLabel' => 'Max 5x', 'todayTotalTokens' => 1_234,
      'limits' => [{ 'label' => 'Session (5-hour)', 'percent' => 0.4 }] }
  end

  def push(overrides = {})
    post '/api/v1/agent_usage',
         params: { agent: 'claude', machine: 'laptop', payload: collector_payload }.merge(overrides),
         headers: headers, as: :json
  end

  it 'records a snapshot from a machine' do
    expect { push }.to change(user.agent_usage_reports, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(user.agent_usage_reports.last.payload['tierLabel']).to eq('Max 5x')
  end

  # One current row per machine: the panel only ever reads the latest, and
  # keeping every push would grow forever for data nothing looks at.
  it 'replaces that machine\'s previous snapshot rather than accumulating' do
    push
    expect { push(payload: collector_payload.merge('todayTotalTokens' => 9_999)) }
      .not_to change(user.agent_usage_reports, :count)

    expect(user.agent_usage_reports.sole.payload['todayTotalTokens']).to eq(9_999)
  end

  it 'keeps machines separate' do
    push
    push(machine: 'desktop')

    expect(user.agent_usage_reports.pluck(:machine)).to contain_exactly('laptop', 'desktop')
  end

  it 'stores the payload verbatim, whatever keys it has' do
    push(payload: { 'somethingNew' => { 'nested' => [1, 2] } })

    expect(user.agent_usage_reports.sole.payload).to eq('somethingNew' => { 'nested' => [1, 2] })
  end

  it 'refuses an unknown agent' do
    push(agent: 'not-an-agent')

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['errors'].join).to include('Agent')
  end

  it 'falls back to now when the reported time is unusable' do
    freeze_time do
      push(reported_at: 'not a time')

      expect(user.agent_usage_reports.sole.reported_at).to eq(Time.current)
    end
  end

  it 'lists what has been reported' do
    push
    get '/api/v1/agent_usage', headers: headers

    expect(response.parsed_body['reports'].first).to include('machine' => 'laptop', 'stale' => false)
  end

  it 'forgets a machine on request' do
    push
    report = user.agent_usage_reports.sole

    expect { delete "/api/v1/agent_usage/#{report.id}", headers: headers }
      .to change(user.agent_usage_reports, :count).by(-1)
  end

  it "does not touch another user's report" do
    theirs = create(:agent_usage_report, user: create(:user))

    delete "/api/v1/agent_usage/#{theirs.id}", headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it 'requires a token' do
    post '/api/v1/agent_usage', params: { agent: 'claude', machine: 'x' }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
