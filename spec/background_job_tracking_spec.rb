require File.dirname(__FILE__) + File::SEPARATOR + 'spec_helper'

module Delayed
  class Job < ActiveRecord::Base
  end
end

describe 'background job tracking' do
  context 'relations' do
    before :each do
      class ::BackgroundJobTest < ActiveRecord::Base
        include ::BackgroundJobTracking::Trackable
        
        has_background_job_tracking
      end
    end

    after :each do
      Object.send(:remove_const, :BackgroundJobTest)
    end

    it 'should have many delayed job trackings' do
      expect(BackgroundJobTest.reflections["delayed_job_trackings"]).not_to be_nil
      expect(BackgroundJobTest.reflections["delayed_job_trackings"].macro).to eq :has_many

    end
    it 'should have many delayed jobs through trackings' do
      expect(BackgroundJobTest.reflections["delayed_jobs"]).not_to be_nil
      expect(BackgroundJobTest.reflections["delayed_jobs"].options[:through]).to eq :delayed_job_trackings
    end

    it 'should default to ::Delayed::Job as the class' do
      expect(BackgroundJobTest.reflections["delayed_jobs"].options[:class_name]).to eq '::Delayed::Job'
    end
  end

  context 'instance scope' do
    before :each do
      class ::BackgroundJobTest < ActiveRecord::Base
        include ::BackgroundJobTracking::Trackable
        
        has_background_job_tracking

        background_job_tracking on: :after_create,
          method_name: :schedule_long_running_thing,
          update_if: Proc.new {|bjt| bjt.needs_updated? }

        def schedule_long_running_thing
          ::Delayed::Job.new # example:  self.delay(:run_at => Date.tomorrow).do_some_long_running_thing
        end

        def do_some_long_running_thing ; end

        def needs_updated? ; true ; end
      end
    end

    after :each do
      Object.send(:remove_const, :BackgroundJobTest)
    end

    context 'method creation' do
      before :each do
        @object_with_jobs = ::BackgroundJobTest.new
      end

      it 'should create a method for the job creation callback to call' do
        expect(@object_with_jobs).to respond_to :background_job_creation_tracking_callback_for_schedule_long_running_thing
      end

      it 'should create a method for the job destroy/reschedule on after_update to call' do
        expect(@object_with_jobs).to respond_to :reschedule_background_job_for_schedule_long_running_thing
      end
    end

    context 'generated instance methods' do
      before :each do
        @object_with_jobs = ::BackgroundJobTest.new
      end

      context 'job creation method' do
        it 'should create a delayed_job_tracking record' do
          allow(@object_with_jobs).to receive(:schedule_long_running_thing).and_return(job = Delayed::Job.new)
          expect(@object_with_jobs).to receive(:create_delayed_job_tracking_for_method_name_and_job).with(:schedule_long_running_thing, job)

          @object_with_jobs.send :background_job_creation_tracking_callback_for_schedule_long_running_thing
        end #job creation method

        context 'calling user defined methods' do
          it 'should track the Delayed::Job returned from the :schedule_long_running_thing method' do
            job = ::Delayed::Job.new
            expect(@object_with_jobs).to receive(:schedule_long_running_thing).and_return(job)
            expect(@object_with_jobs).to receive(:create_delayed_job_tracking_for_method_name_and_job).with(:schedule_long_running_thing, job)

            @object_with_jobs.save
          end

          it 'should not attempt to add a non Delayed::Job instance to the delayed_jobs association' do
            expect(@object_with_jobs).to receive(:schedule_long_running_thing).and_return(Object.new)
            expect(@object_with_jobs).not_to receive(:create_delayed_job_tracking_for_method_name_and_job)

            @object_with_jobs.save!
          end
        end #calling user defined methods
      end # job creation method

      context 'for deleting and rescheduling jobs after_update' do
        before :each do
          @object_with_jobs = ::BackgroundJobTest.create
          # allow(@object_with_jobs).to receive(:new_record?).and_return(false)
        end

        it 'should call the generated after_update method' do
          expect(@object_with_jobs).to receive :reschedule_background_job_for_schedule_long_running_thing
          @object_with_jobs.save
        end

        it 'should destroy jobs created by that method name' do
          expect(@object_with_jobs).to receive(:destroy_jobs_created_by_method_name).with(:schedule_long_running_thing)

          @object_with_jobs.save
        end

        it 'should also destroy the trackings created by that method name' do
          expect(@object_with_jobs).to receive(:destroy_delayed_job_trackings_created_by_method_name).with(:schedule_long_running_thing)

          @object_with_jobs.save
        end

        it 'should re-run the scheduling method' do
          expect(@object_with_jobs).to receive(:background_job_creation_tracking_callback_for_schedule_long_running_thing)

          @object_with_jobs.save
        end
      end
    end # generated instance methods

    context 'instance methods' do
      before :each do
        @object_with_jobs = ::BackgroundJobTest.new
        @object_with_jobs.id = 66
        allow(@object_with_jobs).to receive(:new_record?).and_return(false)
      end

      context 'run_and_track_job_for' do
        it 'should run the method that schedules and tracks background jobs (background_job_creation_tracking_callback_for_schedule_long_running_thing in our example)' do
          expect(@object_with_jobs).to receive(:background_job_creation_tracking_callback_for_schedule_long_running_thing)

          @object_with_jobs.run_and_track_job_for :schedule_long_running_thing
        end
      end

      context 'run_and_reschedule_job_for' do
        it 'should run the method that reschedules and tracks background jobs (reschedule_background_job_for_schedule_long_running_thing in our example)' do
          expect(@object_with_jobs).to receive(:reschedule_background_job_for_schedule_long_running_thing)

          @object_with_jobs.run_and_reschedule_job_for :schedule_long_running_thing
        end
      end

      context 'create_delayed_job_tracking_for_method_name_and_job' do
        it 'should create a delayed_job_tracking for the job with the method name' do
          job = double
          allow(@object_with_jobs).to receive(:delayed_job_trackings).and_return(trackings_association = double)

          expect(trackings_association).to receive(:create).with({:created_by_method_name => 'schedule_long_running_thing', :delayed_job => job})

          @object_with_jobs.send(:create_delayed_job_tracking_for_method_name_and_job, :schedule_long_running_thing, job)
        end
      end

      context 'destroy_jobs_created_by_method_name' do
        it 'should destroy the jobs if it finds any' do
          jobs = [ double('delayed_job', '[]' => 1) ]
          method_name = :schedule_ninety_horses
          expect(@object_with_jobs).to receive(:get_jobs_created_by_method_name).with(method_name).and_return(jobs)
          expect(@object_with_jobs.class.background_job_class).to receive(:destroy).with([1])

          @object_with_jobs.send(:destroy_jobs_created_by_method_name, method_name)
        end

        it 'should not bother to  destroy if it does not find any jobs' do
          jobs = []
          method_name = :schedule_ninety_horses
          expect(@object_with_jobs).to receive(:get_jobs_created_by_method_name).with(method_name).and_return(jobs)

          expect(@object_with_jobs.class.background_job_class).not_to receive(:destroy)

          @object_with_jobs.send(:destroy_jobs_created_by_method_name, method_name)
        end
      end

      context 'get_delayed_job_trackings_created_by_method_name' do
        it 'should find jobs created by that method ' do
          relation = @object_with_jobs.send(:get_delayed_job_trackings_created_by_method_name, :schedule_long_running_thing)
          
          cleaned_query = relation.to_sql.gsub(/\"/, "")

          expect(cleaned_query).to eq %{SELECT delayed_job_trackings.* FROM delayed_job_trackings WHERE delayed_job_trackings.job_owner_id = 66 AND delayed_job_trackings.job_owner_type = 'BackgroundJobTest' AND delayed_job_trackings.created_by_method_name = 'schedule_long_running_thing'}
        end
      end

      context 'destroy_delayed_job_trackings_created_by_method_name' do
        it 'should destroy those trackings if they exist' do
          trackings = [ double('trackings', '[]' => 1) ]
          allow(@object_with_jobs).to receive(:get_delayed_job_trackings_created_by_method_name).with(:schedule_long_running_thing).and_return(trackings)
          expect(DelayedJobTracking).to receive(:destroy).with([1])

          @object_with_jobs.send(:destroy_delayed_job_trackings_created_by_method_name, :schedule_long_running_thing)
        end

        it 'should not bother if empty' do
          trackings = []
          allow(@object_with_jobs).to receive(:get_delayed_job_trackings_created_by_method_name).with(:schedule_long_running_thing).and_return(trackings)

          expect(DelayedJobTracking).not_to receive(:destroy).with(trackings)

          @object_with_jobs.send(:destroy_delayed_job_trackings_created_by_method_name, :schedule_long_running_thing)
        end
      end
    end

    context 'callbacks' do
      before :each do
        @object_with_jobs = ::BackgroundJobTest.new
      end

      it 'should call the generated callback method after create' do
        expect(@object_with_jobs).to receive(:background_job_creation_tracking_callback_for_schedule_long_running_thing)

        @object_with_jobs.save!
      end

      it 'should call the generated callback for after_update' do
        allow(@object_with_jobs).to receive(:new_record?).and_return(false)
        @object_with_jobs.id = 66

        expect(@object_with_jobs).to receive(:reschedule_background_job_for_schedule_long_running_thing)

        @object_with_jobs.save!
      end
    end
  end

  describe 'Delayed::Backend::ActiveRecord::Job' do
    it 'should have a dependent destroy on trackings' do
      expect(Delayed::Backend::ActiveRecord::Job.reflections["delayed_job_tracking"].options[:dependent]).to eq :destroy
    end
  end

end
